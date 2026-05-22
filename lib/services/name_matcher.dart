// Name matching logic for MSP active recall.
// Each matching strategy is independently configurable via its own Config class,
// and all thresholds are plain numeric fields that can be tweaked for gameplay feel.

import 'dart:math';

// ── Configuration classes ─────────────────────────────────────────────────────

/// Controls Unicode normalisation applied before any comparison.
class NormalizationConfig {
  /// Whether normalisation is applied at all.
  final bool enabled;

  /// Replace accented characters with ASCII equivalents (é→e, ü→u, etc.).
  final bool stripDiacritics;

  /// Fold input to lowercase before comparison.
  final bool caseFold;

  /// Convert hyphens and apostrophes to spaces, strip remaining punctuation.
  final bool stripPunctuation;

  const NormalizationConfig({
    this.enabled = true,
    this.stripDiacritics = true,
    this.caseFold = true,
    this.stripPunctuation = true,
  });
}

/// Controls whether recognised nickname/formal-name pairs are tried.
class NicknameConfig {
  final bool enabled;

  const NicknameConfig({this.enabled = true});
}

/// Controls Soundex phonetic fallback for last-name matching.
class PhoneticConfig {
  final bool enabled;

  /// Minimum Jaro-Winkler score required on the first name when last names
  /// match only phonetically (prevents e.g. "Bob Smith" matching "Ann Smith").
  final double firstNameMinScore;

  const PhoneticConfig({
    this.enabled = true,
    this.firstNameMinScore = 0.60,
  });
}

/// Controls Jaro-Winkler fuzzy matching thresholds and comment tiers.
class FuzzyConfig {
  /// Minimum JW score on the full (or combined per-part) name to accept as
  /// a correct guess.  Lower = more forgiving.
  final double acceptThreshold;

  /// JW score above which the charming comment is "Perfect spelling!" style.
  final double perfectThreshold;

  /// JW score above which the comment is "Almost perfect!" style.
  final double nearPerfectThreshold;

  /// JW score above which the comment is "Close enough!" style.
  /// Below this (but >= acceptThreshold) gives "Near enough!" style.
  final double closeThreshold;

  /// Jaro-Winkler prefix-bonus weight.  Standard default is 0.1; max is 0.25.
  final double prefixWeight;

  /// Weight given to last-name similarity when combining per-part scores
  /// (first-name weight is 1 − lastNameWeight).
  final double lastNameWeight;

  /// Minimum last-name JW score required for the per-part path to fire.
  final double lastNameMinScore;

  const FuzzyConfig({
    this.acceptThreshold = 0.82,
    this.perfectThreshold = 0.97,
    this.nearPerfectThreshold = 0.92,
    this.closeThreshold = 0.87,
    this.prefixWeight = 0.1,
    this.lastNameWeight = 0.60,
    this.lastNameMinScore = 0.75,
  });
}

/// Aggregate config passed to [NameMatcher].
class MatchConfig {
  final NormalizationConfig normalization;
  final NicknameConfig nicknames;
  final PhoneticConfig phonetics;
  final FuzzyConfig fuzzy;

  const MatchConfig({
    this.normalization = const NormalizationConfig(),
    this.nicknames = const NicknameConfig(),
    this.phonetics = const PhoneticConfig(),
    this.fuzzy = const FuzzyConfig(),
  });

  static const MatchConfig defaultConfig = MatchConfig();
}

// ── Result types ──────────────────────────────────────────────────────────────

enum MatchMethod { exact, nickname, fuzzy, phonetic }

class MatchResult {
  final bool isCorrect;
  final double score;

  /// A charming comment on match quality shown to the player, e.g. "Close enough!".
  final String comment;

  final MatchMethod? method;

  const MatchResult({
    required this.isCorrect,
    required this.score,
    required this.comment,
    this.method,
  });

  static const MatchResult noMatch =
      MatchResult(isCorrect: false, score: 0, comment: '', method: null);
}

// ── Nickname dictionary ───────────────────────────────────────────────────────
// Maps each recognised form to a list of equivalents.  The matcher tries
// substituting the input's first word with every alias before fuzzy scoring.

const Map<String, List<String>> _nicknames = {
  'alexander': ['alex', 'alec', 'aleck', 'sandy'],
  'alex': ['alexander', 'alec', 'sandy'],
  'alec': ['alexander', 'alex'],
  'james': ['jim', 'jimmy', 'jamie'],
  'jim': ['james', 'jamie'],
  'jamie': ['james', 'jim'],
  'william': ['will', 'bill', 'billy', 'willie', 'willy'],
  'willie': ['william', 'will', 'bill'],
  'bill': ['william', 'will', 'willie'],
  'robert': ['rob', 'bob', 'robbie', 'bobby'],
  'bob': ['robert', 'rob', 'robbie'],
  'rob': ['robert', 'bob'],
  'david': ['dave', 'davie'],
  'dave': ['david', 'davie'],
  'michael': ['mike', 'mick', 'mickey'],
  'mike': ['michael'],
  'thomas': ['tom', 'tommy'],
  'tom': ['thomas', 'tommy'],
  'andrew': ['andy', 'drew'],
  'andy': ['andrew'],
  'patrick': ['pat', 'paddy'],
  'pat': ['patrick'],
  'margaret': ['maggie', 'meg', 'peggy'],
  'maggie': ['margaret', 'meg'],
  'meg': ['margaret', 'maggie'],
  'elizabeth': ['liz', 'beth', 'betty', 'eliza', 'libby'],
  'liz': ['elizabeth'],
  'jennifer': ['jenny', 'jen'],
  'jenny': ['jennifer', 'jen'],
  'jacqueline': ['jackie', 'jacqui'],
  'jackie': ['jacqueline', 'jacqui'],
  'gillian': ['gill', 'jill'],
  'gill': ['gillian'],
  'claire': ['clare'],
  'clare': ['claire'],
  'alison': ['ali', 'allie', 'allyson'],
  'ali': ['alison'],
  'stephen': ['steve', 'steven'],
  'steven': ['stephen', 'steve'],
  'steve': ['stephen', 'steven'],
  'christopher': ['chris', 'kit'],
  'chris': ['christopher'],
  'kristopher': ['kris', 'chris', 'kristof'],
  'kris': ['kristopher', 'chris'],
  'anne': ['ann', 'annie'],
  'ann': ['anne'],
  'helen': ['nell', 'nellie'],
  'mairi': ['mary', 'marie'],
  'marie': ['mairi', 'mary'],
  'mary': ['mairi', 'marie'],
  'siobhian': ['siobhan', 'chevonne', 'shivawn'],
  'siobhan': ['siobhian', 'chevonne'],
  'alyn': ['alan', 'alun'],
  'alan': ['alyn', 'alun'],
  'alun': ['alan', 'alyn'],
  'john': ['jonny', 'johnny', 'ian'],
  'angus': ['gus'],
  'gus': ['angus'],
  'kenneth': ['ken', 'kenny'],
  'ken': ['kenneth'],
  'richard': ['rich', 'rick', 'dick'],
  'ian': ['john'],
  'donald': ['don', 'donnie'],
  'don': ['donald'],
  'neil': ['neal'],
  'neal': ['neil'],
  'mark': ['marc'],
  'marc': ['mark'],
  'katherine': ['kate', 'katy', 'katie', 'kath', 'kathryn'],
  'katharine': ['kate', 'katy', 'katie', 'kath'],
  'kathryn': ['kate', 'katy', 'katie', 'kath', 'katherine'],
  'kate': ['katharine', 'katherine', 'kathryn', 'katy'],
  'katy': ['kate', 'kathryn', 'katherine'],
  'kayleigh': ['kayley', 'kaylee', 'kaleigh'],
  'colm': ['column', 'collum', 'callum'],
  'george': ['georgie'],
  'pauline': ['paula'],
  'maree': ['marie', 'mary'],
  'collette': ['colette'],
  'colette': ['collette'],
  'kirsten': ['kirstin', 'kirsty'],
  'kirsty': ['kirsten', 'kirstin'],
};

// ── Diacritic normalisation map ───────────────────────────────────────────────

const Map<String, String> _diacritics = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
  'æ': 'ae', 'ç': 'c',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
  'ñ': 'n',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
  'ý': 'y', 'ÿ': 'y', 'ß': 'ss',
};

// ── Core algorithm implementations ────────────────────────────────────────────

String _stripDiacritics(String s) {
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    buf.write(_diacritics[ch] ?? ch);
  }
  return buf.toString();
}

String _normalize(String s, NormalizationConfig cfg) {
  if (!cfg.enabled) return s;
  if (cfg.stripDiacritics) s = _stripDiacritics(s);
  if (cfg.caseFold) s = s.toLowerCase();
  if (cfg.stripPunctuation) {
    s = s.replaceAll(RegExp(r"['\-]"), ' ');
    s = s.replaceAll(RegExp(r'[^\w\s]'), '');
  }
  return s.trim().replaceAll(RegExp(r'\s+'), ' ');
}

double _jaroSimilarity(String s1, String s2) {
  if (s1 == s2) return 1.0;
  if (s1.isEmpty || s2.isEmpty) return 0.0;

  final matchDist = max(s1.length, s2.length) ~/ 2 - 1;
  final effectiveDist = matchDist < 0 ? 0 : matchDist;

  final s1Matches = List<bool>.filled(s1.length, false);
  final s2Matches = List<bool>.filled(s2.length, false);

  var matches = 0;
  var transpositions = 0;

  for (var i = 0; i < s1.length; i++) {
    final start = max(0, i - effectiveDist);
    final end = min(i + effectiveDist + 1, s2.length);
    for (var j = start; j < end; j++) {
      if (s2Matches[j] || s1[i] != s2[j]) continue;
      s1Matches[i] = true;
      s2Matches[j] = true;
      matches++;
      break;
    }
  }

  if (matches == 0) return 0.0;

  var k = 0;
  for (var i = 0; i < s1.length; i++) {
    if (!s1Matches[i]) continue;
    while (!s2Matches[k]) {
      k++;
    }
    if (s1[i] != s2[k]) transpositions++;
    k++;
  }

  return (matches / s1.length +
          matches / s2.length +
          (matches - transpositions / 2.0) / matches) /
      3.0;
}

double _jaroWinkler(String s1, String s2, double p) {
  final jaro = _jaroSimilarity(s1, s2);
  final maxPrefix = min(4, min(s1.length, s2.length));
  var prefix = 0;
  while (prefix < maxPrefix && s1[prefix] == s2[prefix]) {
    prefix++;
  }
  return jaro + prefix * p * (1.0 - jaro);
}

String _soundex(String name) {
  if (name.isEmpty) return '';
  final upper = name.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
  if (upper.isEmpty) return '';

  const table = {
    'B': '1', 'F': '1', 'P': '1', 'V': '1',
    'C': '2', 'G': '2', 'J': '2', 'K': '2',
    'Q': '2', 'S': '2', 'X': '2', 'Z': '2',
    'D': '3', 'T': '3',
    'L': '4',
    'M': '5', 'N': '5',
    'R': '6',
  };

  var result = upper[0];
  var lastCode = table[upper[0]] ?? '';

  for (var i = 1; i < upper.length && result.length < 4; i++) {
    final code = table[upper[i]] ?? '';
    if (code.isNotEmpty && code != lastCode) result += code;
    if (code.isNotEmpty) lastCode = code;
  }

  return result.padRight(4, '0');
}

// ── Comment generation ────────────────────────────────────────────────────────

const _perfectComments = [
  'Perfect spelling!',
  'Spot on!',
  'Flawless!',
  'Letter perfect!',
  'Textbook!',
];

const _nearPerfectComments = [
  'Almost perfect!',
  'Just a tiny slip!',
  'Nearly there!',
  'One away!',
];

const _closeComments = [
  'Close enough!',
  "We'll allow it!",
  'You clearly knew!',
  'Good enough!',
];

const _nearEnoughComments = [
  'Near enough!',
  'We got your drift!',
  "We'll give it to you!",
];

const _nicknameComments = [
  'The nickname counts!',
  'We know who you mean!',
  'Nickname accepted!',
];

const _phoneticComments = [
  'Sounded right to us!',
  'Close enough by ear!',
  'Phonetically spot on!',
];

String _pick(List<String> pool, String seed) {
  final hash = seed.codeUnits.fold(0, (a, b) => a ^ b);
  return pool[hash.abs() % pool.length];
}

String _generateComment(
    double score, MatchMethod method, FuzzyConfig cfg, String inputSeed) {
  if (method == MatchMethod.nickname) return _pick(_nicknameComments, inputSeed);
  if (method == MatchMethod.phonetic) return _pick(_phoneticComments, inputSeed);
  if (method == MatchMethod.exact || score >= cfg.perfectThreshold) {
    return _pick(_perfectComments, inputSeed);
  }
  if (score >= cfg.nearPerfectThreshold) return _pick(_nearPerfectComments, inputSeed);
  if (score >= cfg.closeThreshold) return _pick(_closeComments, inputSeed);
  return _pick(_nearEnoughComments, inputSeed);
}

// ── Main matcher ──────────────────────────────────────────────────────────────

class NameMatcher {
  final MatchConfig config;

  const NameMatcher({this.config = MatchConfig.defaultConfig});

  MatchResult match(String input, String target) {
    final normInput = _normalize(input, config.normalization);
    final normTarget = _normalize(target, config.normalization);

    // 1. Exact match after normalisation
    if (normInput == normTarget) {
      return MatchResult(
        isCorrect: true,
        score: 1.0,
        comment: _generateComment(1.0, MatchMethod.exact, config.fuzzy, input),
        method: MatchMethod.exact,
      );
    }

    // 2. Nickname substitution — try replacing the first word with all known
    //    equivalents, then score each candidate with JW
    if (config.nicknames.enabled) {
      for (final candidate in _expandNicknames(normInput)) {
        if (candidate == normTarget) {
          return MatchResult(
            isCorrect: true,
            score: 0.99,
            comment:
                _generateComment(0.99, MatchMethod.nickname, config.fuzzy, input),
            method: MatchMethod.nickname,
          );
        }
        final jwScore =
            _jaroWinkler(candidate, normTarget, config.fuzzy.prefixWeight);
        if (jwScore >= config.fuzzy.acceptThreshold) {
          return MatchResult(
            isCorrect: true,
            score: jwScore,
            comment: _generateComment(
                jwScore, MatchMethod.nickname, config.fuzzy, input),
            method: MatchMethod.nickname,
          );
        }
      }
    }

    // 3. Jaro-Winkler on the full normalised name
    final jwFull = _jaroWinkler(normInput, normTarget, config.fuzzy.prefixWeight);
    if (jwFull >= config.fuzzy.acceptThreshold) {
      return MatchResult(
        isCorrect: true,
        score: jwFull,
        comment:
            _generateComment(jwFull, MatchMethod.fuzzy, config.fuzzy, input),
        method: MatchMethod.fuzzy,
      );
    }

    // 3b. Per-part JW: compare first and last names separately, combining with
    //     a configurable weight so a well-known last name rescues a fuzzy first.
    final inputParts =
        normInput.split(' ').where((s) => s.isNotEmpty).toList();
    final targetParts =
        normTarget.split(' ').where((s) => s.isNotEmpty).toList();

    if (inputParts.length >= 2 && targetParts.length >= 2) {
      final jwLast = _jaroWinkler(
          inputParts.last, targetParts.last, config.fuzzy.prefixWeight);
      final jwFirst = _jaroWinkler(
          inputParts.first, targetParts.first, config.fuzzy.prefixWeight);
      final combined = jwLast * config.fuzzy.lastNameWeight +
          jwFirst * (1.0 - config.fuzzy.lastNameWeight);
      if (combined >= config.fuzzy.acceptThreshold &&
          jwLast >= config.fuzzy.lastNameMinScore) {
        return MatchResult(
          isCorrect: true,
          score: combined,
          comment: _generateComment(
              combined, MatchMethod.fuzzy, config.fuzzy, input),
          method: MatchMethod.fuzzy,
        );
      }
    }

    // 4. Soundex phonetic fallback on the last name
    if (config.phonetics.enabled &&
        inputParts.isNotEmpty &&
        targetParts.isNotEmpty) {
      final sdxInput = _soundex(inputParts.last);
      final sdxTarget = _soundex(targetParts.last);
      if (sdxInput == sdxTarget && sdxInput != '0000') {
        final jwFirst = inputParts.length > 1 && targetParts.length > 1
            ? _jaroWinkler(
                inputParts.first, targetParts.first, config.fuzzy.prefixWeight)
            : 1.0;
        if (jwFirst >= config.phonetics.firstNameMinScore) {
          return MatchResult(
            isCorrect: true,
            score: 0.85,
            comment:
                _generateComment(0.85, MatchMethod.phonetic, config.fuzzy, input),
            method: MatchMethod.phonetic,
          );
        }
      }
    }

    return MatchResult.noMatch;
  }

  /// Generates all candidate strings formed by replacing the first word of
  /// [normalizedName] with each of its known nickname/alias equivalents.
  Set<String> _expandNicknames(String normalizedName) {
    final parts =
        normalizedName.split(' ').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return {normalizedName};

    final firstWord = parts.first;
    final rest = parts.skip(1).toList();

    final aliases = <String>{
      ...(_nicknames[firstWord] ?? []),
      for (final entry in _nicknames.entries)
        if (entry.value.contains(firstWord)) entry.key,
    };

    return {
      for (final alias in aliases) [alias, ...rest].join(' '),
    };
  }
}
