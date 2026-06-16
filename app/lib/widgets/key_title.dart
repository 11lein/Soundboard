/// Text-wrapping for the tiny square key tiles on the soundboard grid.
///
/// A tile only has room for a few short lines, so a title is broken up so it
/// still reads naturally instead of being cut mid-word. The algorithm:
///   - a line break is allowed only *before* a non-lowercase character (so
///     "AirHorn" splits into "Air"/"Horn" and words stay intact), or anywhere
///     inside a single lowercase run that is itself longer than the 12-char
///     line budget (hard split);
///   - short fragments keep merging onto the current line until it reaches ~6
///     characters, then it breaks at the next opportunity, which produces
///     shorter, more even lines;
///   - at most three lines; if text is left over, the third line is truncated
///     with an ellipsis.
///
/// Pure (no widget/state dependencies) so it can be unit-tested directly and
/// its result cached per title by the caller.
String wrapKeyTitle(String s) {
  bool isLower(String ch) {
    final c = ch.codeUnitAt(0);
    return (c >= 0x61 && c <= 0x7a) || 'äöüß'.contains(ch);
  }

  // Split into chunks; each chunk starts at a break-allowed position
  // (start of string or any non-lowercase character).
  final chunks = <String>[];
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    final ch = s[i];
    if (i > 0 && !isLower(ch)) {
      chunks.add(buf.toString());
      buf.clear();
    }
    buf.write(ch);
  }
  if (buf.isNotEmpty) chunks.add(buf.toString());

  final lines = <String>[];
  String cur = '';
  bool more = false; // content left over after 3 lines
  void pushCur() {
    if (cur.isNotEmpty) {
      lines.add(cur);
      cur = '';
    }
  }

  outer:
  for (var chunk in chunks) {
    // Hard-split a chunk that is itself longer than 12 (all lowercase run).
    while (chunk.length > 12) {
      pushCur();
      if (lines.length >= 3) {
        more = true;
        break outer;
      }
      lines.add(chunk.substring(0, 12));
      chunk = chunk.substring(12);
    }
    if (chunk.isEmpty) continue;
    if (cur.isEmpty) {
      cur = chunk;
    } else if (cur.length < 6 && cur.length + chunk.length <= 12) {
      // Only keep merging while the line is still short; once it reaches ~6
      // characters, break at the next opportunity (shorter, tidier lines).
      cur += chunk;
    } else {
      if (lines.length >= 3) {
        more = true;
        break outer;
      }
      lines.add(cur);
      cur = chunk;
    }
  }
  if (!more && cur.isNotEmpty) {
    if (lines.length < 3) {
      lines.add(cur);
    } else {
      more = true;
    }
  }
  if (more && lines.length == 3) {
    final last = lines[2];
    lines[2] = '${last.length >= 12 ? last.substring(0, 11) : last}…';
  }
  return lines.join('\n');
}
