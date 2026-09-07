import 'package:flutter/painting.dart';

/// Minimal SVG path-data parser.
///
/// Flutter ships no way to build a [Path] from an SVG `d` string and we don't
/// depend on `flutter_svg`, so this covers the subset we actually embed:
/// `M/m L/l H/h V/v C/c S/s Q/q T/t Z/z`. Elliptical arcs (`A/a`) are not
/// supported.
Path parseSvgPath(String d) {
  final path = Path();
  final tokens = _tokenize(d);
  var i = 0;

  // Current point, subpath start, and the previous cubic/quad control point
  // (for the smooth `S`/`T` commands).
  var cx = 0.0, cy = 0.0;
  var startX = 0.0, startY = 0.0;
  double? lastCubicCtrlX, lastCubicCtrlY;
  double? lastQuadCtrlX, lastQuadCtrlY;
  var lastCmd = '';

  double num() => tokens[i++] as double;
  bool moreNumbers() => i < tokens.length && tokens[i] is double;

  while (i < tokens.length) {
    var cmd = tokens[i] is String ? tokens[i++] as String : _implicitCmd(lastCmd);
    final rel = cmd == cmd.toLowerCase();
    final u = cmd.toUpperCase();

    switch (u) {
      case 'M':
        var x = num(), y = num();
        if (rel) {
          x += cx;
          y += cy;
        }
        path.moveTo(x, y);
        cx = startX = x;
        cy = startY = y;
        // Subsequent coordinate pairs are implicit line-tos.
        while (moreNumbers()) {
          var lx = num(), ly = num();
          if (rel) {
            lx += cx;
            ly += cy;
          }
          path.lineTo(lx, ly);
          cx = lx;
          cy = ly;
        }
        break;
      case 'L':
        while (moreNumbers()) {
          var x = num(), y = num();
          if (rel) {
            x += cx;
            y += cy;
          }
          path.lineTo(x, y);
          cx = x;
          cy = y;
        }
        break;
      case 'H':
        while (moreNumbers()) {
          var x = num();
          if (rel) x += cx;
          path.lineTo(x, cy);
          cx = x;
        }
        break;
      case 'V':
        while (moreNumbers()) {
          var y = num();
          if (rel) y += cy;
          path.lineTo(cx, y);
          cy = y;
        }
        break;
      case 'C':
        while (moreNumbers()) {
          var x1 = num(), y1 = num(), x2 = num(), y2 = num(), x = num(), y = num();
          if (rel) {
            x1 += cx;
            y1 += cy;
            x2 += cx;
            y2 += cy;
            x += cx;
            y += cy;
          }
          path.cubicTo(x1, y1, x2, y2, x, y);
          lastCubicCtrlX = x2;
          lastCubicCtrlY = y2;
          cx = x;
          cy = y;
        }
        break;
      case 'S':
        while (moreNumbers()) {
          var x2 = num(), y2 = num(), x = num(), y = num();
          if (rel) {
            x2 += cx;
            y2 += cy;
            x += cx;
            y += cy;
          }
          final reflectValid = lastCmd.toUpperCase() == 'C' || lastCmd.toUpperCase() == 'S';
          final x1 = reflectValid ? 2 * cx - lastCubicCtrlX! : cx;
          final y1 = reflectValid ? 2 * cy - lastCubicCtrlY! : cy;
          path.cubicTo(x1, y1, x2, y2, x, y);
          lastCubicCtrlX = x2;
          lastCubicCtrlY = y2;
          cx = x;
          cy = y;
          lastCmd = rel ? 's' : 'S';
        }
        break;
      case 'Q':
        while (moreNumbers()) {
          var x1 = num(), y1 = num(), x = num(), y = num();
          if (rel) {
            x1 += cx;
            y1 += cy;
            x += cx;
            y += cy;
          }
          path.quadraticBezierTo(x1, y1, x, y);
          lastQuadCtrlX = x1;
          lastQuadCtrlY = y1;
          cx = x;
          cy = y;
        }
        break;
      case 'T':
        while (moreNumbers()) {
          var x = num(), y = num();
          if (rel) {
            x += cx;
            y += cy;
          }
          final reflectValid = lastCmd.toUpperCase() == 'Q' || lastCmd.toUpperCase() == 'T';
          final x1 = reflectValid ? 2 * cx - lastQuadCtrlX! : cx;
          final y1 = reflectValid ? 2 * cy - lastQuadCtrlY! : cy;
          path.quadraticBezierTo(x1, y1, x, y);
          lastQuadCtrlX = x1;
          lastQuadCtrlY = y1;
          cx = x;
          cy = y;
          lastCmd = rel ? 't' : 'T';
        }
        break;
      case 'Z':
        path.close();
        cx = startX;
        cy = startY;
        break;
      default:
        throw FormatException('Unsupported SVG path command: $cmd');
    }
    if (u != 'S' && u != 'T') lastCmd = cmd;
  }
  return path;
}

String _implicitCmd(String lastCmd) {
  if (lastCmd.isEmpty) {
    throw const FormatException('SVG path must start with a command');
  }
  // After an M/m, bare coordinate pairs are line-tos.
  if (lastCmd == 'M') return 'L';
  if (lastCmd == 'm') return 'l';
  return lastCmd;
}

/// Splits a path string into command letters ([String]) and numbers ([double]).
List<Object> _tokenize(String d) {
  final out = <Object>[];
  final buf = StringBuffer();

  void flush() {
    if (buf.isNotEmpty) {
      out.add(double.parse(buf.toString()));
      buf.clear();
    }
  }

  for (var k = 0; k < d.length; k++) {
    final ch = d[k];
    if (RegExp(r'[a-zA-Z]').hasMatch(ch)) {
      flush();
      out.add(ch);
    } else if (ch == ' ' || ch == ',' || ch == '\n' || ch == '\t' || ch == '\r') {
      flush();
    } else if (ch == '-' || ch == '+') {
      // A sign starts a new number unless it follows an exponent marker.
      final prev = buf.isEmpty ? '' : buf.toString()[buf.length - 1];
      if (buf.isNotEmpty && prev != 'e' && prev != 'E') flush();
      buf.write(ch);
    } else if (ch == '.') {
      // A second '.' in the running buffer starts a new number.
      if (buf.toString().contains('.')) flush();
      buf.write(ch);
    } else {
      buf.write(ch);
    }
  }
  flush();
  return out;
}
