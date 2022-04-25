// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'http_callback_handler.dart';
import 'model/http_cookie.dart';
import 'model/http_redirect_info.dart';

/// Represents the server's response to a request.
///
/// The body of a [HttpClientResponse] object is a [Stream] of data from the
/// server.
/// Listen to the body to handle the data and be notified when the entire body
/// is received.
abstract class HttpClientResponse extends Stream<List<int>> {
  Map<String, List<String>> get headers;

  bool get isRedirects;

  List<RedirectInfo> get redirects;

  int get statusCode;

  int get contentLength;

  List<Cookie> get cookies;

  /// protocol will be updated after response ended;
  String get negotiatedProtocol;
}

/// Implementation of [HttpClientResponse].
///
/// Takes instance of callback handler and registers [listen] callbacks to the
/// stream.
class HttpClientResponseImpl extends HttpClientResponse {
  final CallbackHandler _handler;
  HttpClientResponseImpl(CallbackHandler handler) : _handler = handler;

  @override
  Map<String, List<String>> get headers => _handler.headers;

  @override
  bool get isRedirects => _handler.redirects.isNotEmpty;

  @override
  List<RedirectInfo> get redirects => _handler.redirects;

  @override
  int get statusCode => _handler.statusCode;

  @override
  int get contentLength => _handler.contentLength;

  @override
  List<Cookie> get cookies => _handler.cookies;

  @override
  String get negotiatedProtocol => _handler.negotiatedProtocol;

  @override
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return _handler.stream.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }
}
