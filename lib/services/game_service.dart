import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/msp.dart';
import 'name_matcher.dart';

class GuessResult {
  final Msp msp;
  final MatchResult nameResult;
  final bool partyCorrect;
  final bool bothCorrect;

  const GuessResult({
    required this.msp,
    required this.nameResult,
    required this.partyCorrect,
    required this.bothCorrect,
  });
}

class GameService {
  final List<Msp> msps;
  final Set<String> _guessedSlugs;
  final NameMatcher _matcher;

  GameService({
    required this.msps,
    required Set<String> initialGuessed,
  })  : _guessedSlugs = Set.from(initialGuessed),
        _matcher = const NameMatcher();

  int get totalCount => msps.length;
  int get guessedCount => _guessedSlugs.length;
  bool get isComplete => guessedCount >= totalCount;

  List<Msp> get _remaining =>
      msps.where((m) => !_guessedSlugs.contains(m.slug)).toList();

  Msp pickNext() {
    final pool = _remaining;
    assert(pool.isNotEmpty, 'pickNext called with no remaining MSPs');
    return pool[Random().nextInt(pool.length)];
  }

  GuessResult submitGuess(Msp msp, String nameInput, String selectedParty) {
    final nameResult = _matcher.match(nameInput, msp.name);
    final partyCorrect = selectedParty == msp.party;
    final bothCorrect = nameResult.isCorrect && partyCorrect;

    if (bothCorrect) {
      _guessedSlugs.add(msp.slug);
      _saveProgress();
    }

    return GuessResult(
      msp: msp,
      nameResult: nameResult,
      partyCorrect: partyCorrect,
      bothCorrect: bothCorrect,
    );
  }

  Future<void> reset() async {
    _guessedSlugs.clear();
    await _saveProgress();
  }

  Future<void> _saveProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('guessed_msps', _guessedSlugs.toList());
  }
}
