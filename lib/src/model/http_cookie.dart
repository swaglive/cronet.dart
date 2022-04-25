import '../exceptions.dart';
import 'http_date.dart';

/// Representation of a cookie. For cookies received by the server as Cookie
/// header values only [name] and [value] properties will be set. When building a
/// cookie for the 'set-cookie' header in the server and when receiving cookies
/// in the client as 'set-cookie' headers all fields can be used.
abstract class Cookie {
  /// The name of the cookie.
  ///
  /// Must be a `token` as specified in RFC 6265.
  ///
  /// The allowed characters in a `token` are the visible ASCII characters,
  /// U+0021 (`!`) through U+007E (`~`), except the separator characters:
  /// `(`, `)`, `<`, `>`, `@`, `,`, `;`, `:`, `\`, `"`, `/`, `[`, `]`, `?`, `=`,
  /// `{`, and `}`.
  late String name;

  /// The value of the cookie.
  ///
  /// Must be a `cookie-value` as specified in RFC 6265.
  ///
  /// The allowed characters in a cookie value are the visible ASCII characters,
  /// U+0021 (`!`) through U+007E (`~`) except the characters:
  /// `"`, `,`, `;` and `\`.
  /// Cookie values may be wrapped in a single pair of double quotes
  /// (U+0022, `"`).
  late String value;

  /// The time at which the cookie expires.
  DateTime? expires;

  /// The number of seconds until the cookie expires. A zero or negative value
  /// means the cookie has expired.
  int? maxAge;

  /// The domain that the cookie applies to.
  String? domain;

  /// The path within the [domain] that the cookie applies to.
  String? path;

  /// Whether to only send this cookie on secure connections.
  bool secure = false;

  /// Whether the cookie is only sent in the HTTP request and is not made
  /// available to client side scripts.
  bool httpOnly = false;

  /// Creates a new cookie setting the name and value.
  ///
  /// [name] and [value] must be composed of valid characters according to RFC
  /// 6265.
  ///
  /// By default the value of `httpOnly` will be set to `true`.
  factory Cookie(String name, String value) => _Cookie(name, value);

  /// Creates a new cookie by parsing a header value from a 'set-cookie'
  /// header.
  factory Cookie.fromSetCookieValue(String value) {
    return _Cookie.fromSetCookieValue(value);
  }

  /// Returns the formatted string representation of the cookie. The
  /// string representation can be used for setting the Cookie or
  /// 'set-cookie' headers
  String toString();
}

class _Cookie implements Cookie {
  String _name;
  String _value;
  DateTime? expires;
  int? maxAge;
  String? domain;
  String? _path;
  bool httpOnly = false;
  bool secure = false;

  _Cookie(String name, String value)
      : _name = _validateName(name),
        _value = _validateValue(value),
        httpOnly = true;

  String get name => _name;
  String get value => _value;

  String? get path => _path;

  set path(String? newPath) {
    _validatePath(newPath);
    _path = newPath;
  }

  set name(String newName) {
    _validateName(newName);
    _name = newName;
  }

  set value(String newValue) {
    _validateValue(newValue);
    _value = newValue;
  }

  _Cookie.fromSetCookieValue(String value)
      : _name = "",
        _value = "" {
    // Parse the 'set-cookie' header value.
    _parseSetCookieValue(value);
  }

  // Parse a 'set-cookie' header value according to the rules in RFC 6265.
  void _parseSetCookieValue(String s) {
    int index = 0;

    bool done() => index == s.length;

    String parseName() {
      int start = index;
      while (!done()) {
        if (s[index] == "=") break;
        index++;
      }
      return s.substring(start, index).trim();
    }

    String parseValue() {
      int start = index;
      while (!done()) {
        if (s[index] == ";") break;
        index++;
      }
      return s.substring(start, index).trim();
    }

    void parseAttributes() {
      String parseAttributeName() {
        int start = index;
        while (!done()) {
          if (s[index] == "=" || s[index] == ";") break;
          index++;
        }
        return s.substring(start, index).trim().toLowerCase();
      }

      String parseAttributeValue() {
        int start = index;
        while (!done()) {
          if (s[index] == ";") break;
          index++;
        }
        return s.substring(start, index).trim().toLowerCase();
      }

      while (!done()) {
        String name = parseAttributeName();
        String value = "";
        if (!done() && s[index] == "=") {
          index++; // Skip the = character.
          value = parseAttributeValue();
        }
        if (name == "expires") {
          expires = HttpDate.parseCookieDate(value);
        } else if (name == "max-age") {
          maxAge = int.parse(value);
        } else if (name == "domain") {
          domain = value;
        } else if (name == "path") {
          path = value;
        } else if (name == "httponly") {
          httpOnly = true;
        } else if (name == "secure") {
          secure = true;
        }
        if (!done()) index++; // Skip the ; character
      }
    }

    _name = _validateName(parseName());
    if (done() || _name.isEmpty) {
      throw HttpException("Failed to parse header value [$s]");
    }
    index++; // Skip the = character.
    _value = _validateValue(parseValue());
    if (done()) return;
    index++; // Skip the ; character.
    parseAttributes();
  }

  String toString() {
    StringBuffer sb = StringBuffer();
    sb
      ..write(_name)
      ..write("=")
      ..write(_value);
    var expires = this.expires;
    if (expires != null) {
      sb
        ..write("; Expires=")
        ..write(HttpDate.format(expires));
    }
    if (maxAge != null) {
      sb
        ..write("; Max-Age=")
        ..write(maxAge);
    }
    if (domain != null) {
      sb
        ..write("; Domain=")
        ..write(domain);
    }
    if (path != null) {
      sb
        ..write("; Path=")
        ..write(path);
    }
    if (secure) sb.write("; Secure");
    if (httpOnly) sb.write("; HttpOnly");
    return sb.toString();
  }

  static String _validateName(String newName) {
    const separators = [
      "(",
      ")",
      "<",
      ">",
      "@",
      ",",
      ";",
      ":",
      "\\",
      '"',
      "/",
      "[",
      "]",
      "?",
      "=",
      "{",
      "}"
    ];
    if (newName == null) throw ArgumentError.notNull("name");
    for (int i = 0; i < newName.length; i++) {
      int codeUnit = newName.codeUnitAt(i);
      if (codeUnit <= 32 ||
          codeUnit >= 127 ||
          separators.contains(newName[i])) {
        throw FormatException(
            "Invalid character in cookie name, code unit: '$codeUnit'",
            newName,
            i);
      }
    }
    return newName;
  }

  static String _validateValue(String newValue) {
    if (newValue == null) throw ArgumentError.notNull("value");
    // Per RFC 6265, consider surrounding "" as part of the value, but otherwise
    // double quotes are not allowed.
    int start = 0;
    int end = newValue.length;
    if (2 <= newValue.length &&
        newValue.codeUnits[start] == 0x22 &&
        newValue.codeUnits[end - 1] == 0x22) {
      start++;
      end--;
    }

    for (int i = start; i < end; i++) {
      int codeUnit = newValue.codeUnits[i];
      if (!(codeUnit == 0x21 ||
          (codeUnit >= 0x23 && codeUnit <= 0x2B) ||
          (codeUnit >= 0x2D && codeUnit <= 0x3A) ||
          (codeUnit >= 0x3C && codeUnit <= 0x5B) ||
          (codeUnit >= 0x5D && codeUnit <= 0x7E))) {
        throw FormatException(
            "Invalid character in cookie value, code unit: '$codeUnit'",
            newValue,
            i);
      }
    }
    return newValue;
  }

  static void _validatePath(String? path) {
    if (path == null) return;
    for (int i = 0; i < path.length; i++) {
      int codeUnit = path.codeUnitAt(i);
      // According to RFC 6265, semicolon and controls should not occur in the
      // path.
      // path-value = <any CHAR except CTLs or ";">
      // CTLs = %x00-1F / %x7F
      if (codeUnit < 0x20 || codeUnit >= 0x7f || codeUnit == 0x3b /*;*/) {
        throw FormatException(
            "Invalid character in cookie path, code unit: '$codeUnit'");
      }
    }
  }
}
