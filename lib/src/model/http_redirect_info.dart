/// Redirect information.
abstract class RedirectInfo {
  /// Returns the status code used for the redirect.
  int get statusCode;

  /// Returns the method used for the redirect.
  String get method;

  /// Returns the location for the redirect.
  Uri get location;

  @override
  String toString() => 'RedirectInfo('
      'statusCode: $statusCode, '
      'method: $method, '
      'location: $location'
      ')';
}

class RedirectInfoImpl implements RedirectInfo {
  @override
  int get statusCode => _statusCode;

  @override
  String get method => _method;

  @override
  Uri get location => _location;

  const RedirectInfoImpl(int statusCode, String method, Uri location)
      : _statusCode = statusCode,
        _method = method,
        _location = location;

  final int _statusCode;
  final String _method;
  final Uri _location;
}
