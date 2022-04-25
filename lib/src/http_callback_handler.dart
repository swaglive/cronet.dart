// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:developer';
import 'dart:ffi';
import 'dart:io' as io;
import 'dart:isolate';
import 'dart:math' as m;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'exceptions.dart';
import 'globals.dart';
import 'model/http_cookie.dart';
import 'model/http_redirect_info.dart';
import 'third_party/cronet/generated_bindings.dart';
import 'wrapper/generated_bindings.dart' as wrpr;

/// Deserializes the message sent by cronet and it's wrapper.
class _CallbackRequestMessage {
  final String method;
  final Uint8List data;

  /// Constructs [method] and [data] from [message].
  factory _CallbackRequestMessage.fromCppMessage(List<dynamic> message) {
    return _CallbackRequestMessage._(
        message[0] as String, message[1] as Uint8List);
  }

  _CallbackRequestMessage._(this.method, this.data);

  @override
  String toString() => 'CppRequest(method: $method)';
}

/// Handles every kind of callbacks that are invoked by messages and
/// data that are sent by [NativePort] from native cronet library.
class CallbackHandler {
  final String httpMethod;
  final ReceivePort receivePort;
  final Pointer<wrpr.SampleExecutor> executor;

  // These are a part of HttpClientRequest Public API.
  bool followRedirects = true;
  int maxRedirects = 5;

  /// Stream controller to allow consumption of data like [HttpClientResponse].
  final _controller = StreamController<List<int>>();

  final Completer<void> isResponseStarted = Completer();

  String _negotiatedProtocol = 'unknown';

  final Map<String, List<String>> _headers = {};

  int _statusCode = 200;

  List<Cookie>? _cookies;

  final List<RedirectInfo> _redirects = [];

  /// Registers the [NativePort] to the cronet side.
  CallbackHandler(this.httpMethod, this.executor, this.receivePort);

  /// [Stream] for [HttpClientResponse].
  Stream<List<int>> get stream {
    return _controller.stream;
  }

  /// [Stream] controller for [HttpClientResponse].
  StreamController<List<int>> get controller => _controller;

  String get negotiatedProtocol => _negotiatedProtocol;

  Map<String, List<String>> get headers => _headers;

  int get statusCode => _statusCode;

  int get contentLength {
    List<String> values = _headers['content-length'] ?? [];
    return values.isEmpty ? 0 : (int.tryParse(values.first) ?? 0);
  }

  List<Cookie> get cookies {
    List<Cookie>? cookies = _cookies;
    if (cookies != null) return cookies;
    cookies = [];
    List<String>? values = headers[io.HttpHeaders.setCookieHeader];
    if (values != null) {
      for (final String value in values) {
        cookies.add(Cookie.fromSetCookieValue(value));
      }
    }
    _cookies = cookies;
    return cookies;
  }

  List<RedirectInfo> get redirects => _redirects;

  // Clean up tasks for a request.
  //
  // We need to call this then whenever we are done with the request.
  void cleanUpRequest(
      Pointer<Cronet_UrlRequest> reqPtr, void Function() cleanUpClient) {
    receivePort.close();
    wrapper.RemoveRequest(reqPtr.cast());
    cleanUpClient();
  }

  /// Checks status of an URL response.
  bool statusChecker(int respCode, Pointer<Utf8> status, int lBound, int uBound,
      void Function() callback) {
    if (!(respCode >= lBound && respCode <= uBound)) {
      // If NOT in range.
      if (status == nullptr) {
        _controller.addError(HttpException('$respCode'));
      } else {
        final statusStr = status.toDartString();
        _controller.addError(
            HttpException(statusStr.isNotEmpty ? statusStr : '$respCode'));
        malloc.free(status);
      }
      callback();
      return false;
    }
    return true;
  }

  void _getAllHeaders(Pointer<Cronet_UrlResponseInfo> info) {
    if (info == nullptr) return;
    final int size = cronet.Cronet_UrlResponseInfo_all_headers_list_size(info);
    for (int i = 0; i < size; i++) {
      final Pointer<Cronet_HttpHeader> header =
          cronet.Cronet_UrlResponseInfo_all_headers_list_at(info, i);
      final String name =
          cronet.Cronet_HttpHeader_name_get(header).cast<Utf8>().toDartString();
      final String value = cronet.Cronet_HttpHeader_value_get(header)
          .cast<Utf8>()
          .toDartString();
      if (!_headers.containsKey(name)) {
        _headers[name] = [value];
      } else {
        (_headers[name] ?? []).add(value);
      }
    }
  }

  void _getNegotiatedProtocol(Pointer<Cronet_UrlResponseInfo> info) {
    if (info == nullptr) return;
    final String protocol =
        cronet.Cronet_UrlResponseInfo_negotiated_protocol_get(info)
            .cast<Utf8>()
            .toDartString();
    _negotiatedProtocol = protocol;
  }

  /// This listens to the messages sent by native cronet library.
  ///
  /// This also invokes the appropriate callbacks that are registered,
  /// according to the network events sent from cronet side.
  void listen(Pointer<Cronet_UrlRequest> reqPtr, void Function() cleanUpClient,
      Uint8List dataToUpload) {
    // Registers the listener on the receivePort.
    //
    // The message parameter contains both the name of the event and
    // the data associated with it.
    receivePort.listen((dynamic message) {
      final reqMessage =
          _CallbackRequestMessage.fromCppMessage(message as List);
      final args = reqMessage.data.buffer.asUint64List();

      /// Count of how many bytes has been uploaded to the server.
      int bytesSent = 0;

      switch (reqMessage.method) {
        case 'OnRedirectReceived':
          {
            final Pointer<Utf8> newLocationPtr =
                Pointer.fromAddress(args[0]).cast<Utf8>();
            final int statusCode = args[1];
            final Pointer<Utf8> statusTextPtf =
                Pointer.fromAddress(args[3]).cast<Utf8>();

            String newLocation = newLocationPtr.toDartString();

            malloc.free(newLocationPtr);
            // If NOT a 3XX status code, throw Exception.
            final status = statusChecker(statusCode, statusTextPtf, 300, 399,
                () => cronet.Cronet_UrlRequest_Cancel(reqPtr));
            if (!status) {
              break;
            }
            if (followRedirects && maxRedirects > 0) {
              final res = cronet.Cronet_UrlRequest_FollowRedirect(reqPtr);
              if (res != Cronet_RESULT.Cronet_RESULT_SUCCESS) {
                cleanUpRequest(reqPtr, cleanUpClient);
                throw UrlRequestError(res);
              }
              _redirects.add(RedirectInfoImpl(
                statusCode,
                httpMethod,
                Uri.parse(newLocation),
              ));
              maxRedirects--;
            } else {
              cronet.Cronet_UrlRequest_Cancel(reqPtr);
            }
          }
          break;

        // When server has sent the initial response.
        case 'OnResponseStarted':
          {
            final int statusCode = args[0];
            final Pointer<Cronet_UrlResponseInfo> infoPtr =
                Pointer.fromAddress(args[1]);
            final Pointer<Cronet_Buffer> bufferPtr =
                Pointer.fromAddress(args[2]);
            final Pointer<Utf8> statusTextPtr =
                Pointer.fromAddress(args[3]).cast<Utf8>();

            _statusCode = statusCode;
            _getAllHeaders(infoPtr);
            _resumeResponse();
            // If NOT a 1XX or 2XX status code, throw Exception.
            final status = statusChecker(statusCode, statusTextPtr, 100, 299,
                () => cronet.Cronet_UrlRequest_Cancel(reqPtr));
            if (!status) {
              break;
            }
            final res = cronet.Cronet_UrlRequest_Read(reqPtr, bufferPtr);
            if (res != Cronet_RESULT.Cronet_RESULT_SUCCESS) {
              throw UrlRequestError(res);
            }
          }
          break;
        // Read a chunk of data.
        //
        // This is where we actually read the response from the server. Data
        // gets added to the stream here. ReadDataCallback is invoked here with
        // data received and no of bytes read.
        case 'OnReadCompleted':
          {
            final Pointer<Cronet_UrlRequest> requestPtr =
                Pointer.fromAddress(args[0]);
            final int statusCode = args[1];
            final Pointer<Cronet_Buffer> bufferPtr =
                Pointer.fromAddress(args[3]);
            final int bytesRead = args[4];
            final Pointer<Utf8> statusTextPtr =
                Pointer.fromAddress(args[5]).cast<Utf8>();

            // If NOT a 1XX or 2XX status code, throw Exception.
            final status = statusChecker(statusCode, statusTextPtr, 100, 299,
                () => cronet.Cronet_UrlRequest_Cancel(reqPtr));
            if (!status) {
              break;
            }
            final data = cronet.Cronet_Buffer_GetData(bufferPtr)
                .cast<Uint8>()
                .asTypedList(bytesRead);
            _controller.sink.add(data.toList(growable: false));
            final res = cronet.Cronet_UrlRequest_Read(requestPtr, bufferPtr);
            if (res != Cronet_RESULT.Cronet_RESULT_SUCCESS) {
              cleanUpRequest(reqPtr, cleanUpClient);
              _controller.addError(UrlRequestError(res));
              _controller.close();
            }
          }
          break;
        // When the request is succesfully done, we will shut down everything.
        case 'OnSucceeded':
          {
            final Pointer<Cronet_UrlResponseInfo> infoPtr =
                Pointer.fromAddress(args[1]);
            _getNegotiatedProtocol(infoPtr);
            cleanUpRequest(reqPtr, cleanUpClient);
            _controller.close();
            cronet.Cronet_UrlRequest_Destroy(reqPtr);
          }
          break;
        // In case of network error, we will shut down everything.
        case 'OnFailed':
          {
            _resumeResponse();
            final errorStrPtr = Pointer.fromAddress(args[0]).cast<Utf8>();
            final error = errorStrPtr.toDartString();
            malloc.free(errorStrPtr);
            cleanUpRequest(reqPtr, cleanUpClient);
            _controller.addError(HttpException(error));
            _controller.close();
            cronet.Cronet_UrlRequest_Destroy(reqPtr);
          }
          break;
        // When the request is cancelled, we will shut down everything.
        case 'OnCanceled':
          {
            _resumeResponse();
            cleanUpRequest(reqPtr, cleanUpClient);
            _controller.close();
            cronet.Cronet_UrlRequest_Destroy(reqPtr);
          }
          break;
        case 'ReadFunc':
          {
            final size =
                cronet.Cronet_Buffer_GetSize(Pointer.fromAddress(args[1]));
            final remainintBytes = dataToUpload.length - bytesSent;
            final chunkSize = m.min(size, remainintBytes);
            final buff =
                cronet.Cronet_Buffer_GetData(Pointer.fromAddress(args[1]))
                    .cast<Uint8>();
            int i = 0;
            // memcopy from our buffer to cronet buffer.
            for (final byte in dataToUpload.getRange(bytesSent, chunkSize)) {
              buff[i] = byte;
              i++;
            }
            bytesSent += chunkSize;
            cronet.Cronet_UploadDataSink_OnReadSucceeded(
                Pointer.fromAddress(args[0]).cast(), chunkSize, false);
            break;
          }
        case 'RewindFunc':
          {
            bytesSent = 0;
            cronet.Cronet_UploadDataSink_OnRewindSucceeded(
                Pointer.fromAddress(args[0]));
            break;
          }
        case 'CloseFunc':
          {
            wrapper.UploadDataProviderDestroy(Pointer.fromAddress(args[0]));
            break;
          }
        default:
          {
            break;
          }
      }
    }, onError: (Object error) {
      log(error.toString());
    });
  }

  void _resumeResponse() {
    if (!isResponseStarted.isCompleted) {
      isResponseStarted.complete();
    }
  }
}
