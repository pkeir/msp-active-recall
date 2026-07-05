import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/link.dart';
import '../models/msp.dart';
import '../services/game_service.dart';

// Party display order: descending seats (2026 election), reverse-alpha on ties.
const List<String> kPartyOrder = [
  'Scottish National Party', // 57 seats
  'Scottish Labour', // 17 seats  (S > R in reverse-alpha)
  'Reform UK', // 17 seats
  'Scottish Green Party', // 15 seats
  'Scottish Conservatives', // 12 seats
  'Scottish Liberal Democrats', // 10 seats
  'No Party Affiliation', //  1 seat
];

const Map<String, int> kPartySeats = {
  'Scottish National Party': 57,
  'Scottish Labour': 17,
  'Reform UK': 17,
  'Scottish Green Party': 15,
  'Scottish Conservatives': 12,
  'Scottish Liberal Democrats': 10,
  'No Party Affiliation': 1,
};

Color _partyColor(String party) => switch (party) {
  'Scottish National Party' => const Color(0xFFF5D800),
  'Scottish Labour' => const Color(0xFFDC241F),
  'Reform UK' => const Color(0xFF12B6CF),
  'Scottish Green Party' => const Color(0xFF009E44),
  'Scottish Conservatives' => const Color(0xFF003087),
  'Scottish Liberal Democrats' => const Color(0xFFFAA61A),
  'No Party Affiliation' => const Color(0xFF78909C),
  _ => Colors.grey,
};

// Returns a text colour that is readable against a lightly-tinted background
// of [partyColor] (opacity ≈ 0.12).
Color _partyTextColor(String party) {
  final c = _partyColor(party);
  return c.computeLuminance() > 0.5 ? Colors.black87 : c;
}

enum _GamePhase { playing, result, complete }

// ── Main screen ───────────────────────────────────────────────────────────────

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.service});

  final GameService service;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late _GamePhase _phase;
  Msp? _currentMsp;
  GuessResult? _lastResult;
  final _nameController = TextEditingController();
  final _nameFocusNode = FocusNode();
  final _nextFocusNode = FocusNode();
  String? _selectedParty;

  GameService get _service => widget.service;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_rebuild);
    if (_service.isComplete) {
      _phase = _GamePhase.complete;
    } else {
      _phase = _GamePhase.playing;
      _currentMsp = _service.pickNext();
    }
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocusNode.dispose();
    _nextFocusNode.dispose();
    super.dispose();
  }

  bool get _canSubmit => _currentMsp != null;

  void _submit() {
    if (!_canSubmit) return;
    final result = _service.submitGuess(
      _currentMsp!,
      _nameController.text.trim(),
      _selectedParty,
    );
    setState(() {
      _lastResult = result;
      _phase = _GamePhase.result;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nextFocusNode.requestFocus();
    });
  }

  void _next() {
    _nameController.clear();
    setState(() {
      _selectedParty = null;
      _lastResult = null;
      if (_service.isComplete) {
        _phase = _GamePhase.complete;
        _currentMsp = null;
      } else {
        _phase = _GamePhase.playing;
        _currentMsp = _service.pickNext();
      }
    });
    if (_phase == _GamePhase.playing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _nameFocusNode.requestFocus();
      });
    }
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset game?'),
        content: const Text('All progress will be cleared. Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _service.reset();
      _nameController.clear();
      setState(() {
        _selectedParty = null;
        _lastResult = null;
        _phase = _GamePhase.playing;
        _currentMsp = _service.pickNext();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF003087),
        foregroundColor: Colors.white,
        title: const Text('MSP Active Recall'),
        actions: [
          IconButton(
            onPressed: _confirmReset,
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset game',
          ),
        ],
      ),
      body: Column(
        children: [
          _ProgressHeader(
            guessed: _service.guessedCount,
            total: _service.totalCount,
          ),
          Expanded(
            child: SelectionArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 20,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: switch (_phase) {
                        _GamePhase.playing => _PlayingView(
                          key: ValueKey(_currentMsp?.slug ?? ''),
                          msp: _currentMsp!,
                          nameController: _nameController,
                          nameFocusNode: _nameFocusNode,
                          selectedParty: _selectedParty,
                          onPartySelected: (p) =>
                              setState(() => _selectedParty = p),
                          canSubmit: _canSubmit,
                          onSubmit: _submit,
                        ),
                        _GamePhase.result => _ResultView(
                          key: ValueKey(
                            'result_${_lastResult?.msp.slug ?? ''}',
                          ),
                          result: _lastResult!,
                          nextFocusNode: _nextFocusNode,
                          onNext: _next,
                        ),
                        _GamePhase.complete => _CompleteView(
                          key: const ValueKey('complete'),
                          total: _service.totalCount,
                          onPlayAgain: () async {
                            await _service.reset();
                            if (!mounted) return;
                            setState(() {
                              _phase = _GamePhase.playing;
                              _currentMsp = _service.pickNext();
                            });
                          },
                        ),
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          const _Footer(),
        ],
      ),
    );
  }
}

// ── Progress header ───────────────────────────────────────────────────────────

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.guessed, required this.total});

  final int guessed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final progress = total > 0 ? guessed / total : 0.0;
    return Container(
      color: const Color(0xFF002060),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFFF5D800),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$guessed / $total',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Playing view ──────────────────────────────────────────────────────────────

class _PlayingView extends StatefulWidget {
  const _PlayingView({
    super.key,
    required this.msp,
    required this.nameController,
    required this.nameFocusNode,
    required this.selectedParty,
    required this.onPartySelected,
    required this.canSubmit,
    required this.onSubmit,
  });

  final Msp msp;
  final TextEditingController nameController;
  final FocusNode nameFocusNode;
  final String? selectedParty;
  final ValueChanged<String> onPartySelected;
  final bool canSubmit;
  final VoidCallback onSubmit;

  @override
  State<_PlayingView> createState() => _PlayingViewState();
}

class _PlayingViewState extends State<_PlayingView> {
  final _partyFocusNode = FocusNode();

  @override
  void dispose() {
    _partyFocusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onPartyKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final parties = kPartyOrder;
    final cur = widget.selectedParty == null
        ? -1
        : parties.indexOf(widget.selectedParty!);
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      widget.onPartySelected(parties[(cur + 1) % parties.length]);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      widget.onPartySelected(parties[cur <= 0 ? parties.length - 1 : cur - 1]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // MSP photo
        Card(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Image.asset(
              widget.msp.imagePath,
              height: 260,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Container(
                height: 260,
                color: Colors.grey.shade200,
                child: const Icon(Icons.person, size: 80, color: Colors.grey),
              ),
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Name input
        Text(
          'Who is this MSP?',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: widget.nameController,
          focusNode: widget.nameFocusNode,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Type their full name…',
            prefixIcon: Icon(Icons.person_outline),
          ),
          onEditingComplete: () {},
        ),

        const SizedBox(height: 20),

        // Party selector — single TAB stop; UP/DOWN move selection
        Text(
          'Which party?',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Focus(
          focusNode: _partyFocusNode,
          onKeyEvent: _onPartyKey,
          child: ListenableBuilder(
            listenable: _partyFocusNode,
            builder: (context, _) {
              final focused = _partyFocusNode.hasFocus;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: focused
                    ? BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      )
                    : null,
                padding: focused ? const EdgeInsets.all(6) : EdgeInsets.zero,
                child: ExcludeFocus(
                  child: Column(
                    children: kPartyOrder
                        .map(
                          (party) => _PartyOption(
                            party: party,
                            selected: party == widget.selectedParty,
                            onTap: () => widget.onPartySelected(party),
                          ),
                        )
                        .toList(),
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 20),

        // Submit
        FilledButton.icon(
          onPressed: widget.canSubmit ? widget.onSubmit : null,
          icon: const Icon(Icons.check),
          label: const Text('Submit'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            textStyle: const TextStyle(fontSize: 16),
          ),
        ),

        const SizedBox(height: 8),
      ],
    );
  }
}

// ── Party option widget ───────────────────────────────────────────────────────

class _PartyOption extends StatelessWidget {
  const _PartyOption({
    required this.party,
    required this.selected,
    required this.onTap,
  });

  final String party;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _partyColor(party);
    final textColor = _partyTextColor(party);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? color : Colors.grey.shade300,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
            color: selected ? color.withAlpha(30) : Colors.white,
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? color : Colors.grey.shade400,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  party,
                  style: TextStyle(
                    color: selected ? textColor : Colors.black87,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              Text(
                '${kPartySeats[party] ?? 0} seat${(kPartySeats[party] ?? 0) == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: 12,
                  color: selected
                      ? textColor.withAlpha(180)
                      : Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Result view ───────────────────────────────────────────────────────────────

class _ResultView extends StatelessWidget {
  const _ResultView({
    super.key,
    required this.result,
    required this.nextFocusNode,
    required this.onNext,
  });

  final GuessResult result;
  final FocusNode nextFocusNode;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final msp = result.msp;
    final correct = result.bothCorrect;
    final bannerColor = correct
        ? const Color(0xFF1B5E20)
        : const Color(0xFF7F0000);
    final bannerIcon = correct ? Icons.check_circle : Icons.cancel;
    final bannerText = correct ? 'Correct!' : 'Not quite!';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: bannerColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(bannerIcon, color: Colors.white, size: 28),
              const SizedBox(width: 10),
              Text(
                bannerText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // MSP photo + name + party side by side
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    msp.imagePath,
                    width: 90,
                    height: 64,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 90,
                      height: 64,
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.person, color: Colors.grey),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        msp.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _PartyBadge(party: msp.party),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Name result
        _ResultRow(
          icon: result.nameResult.isCorrect ? Icons.check : Icons.close,
          iconColor: result.nameResult.isCorrect
              ? Colors.green.shade700
              : Colors.red.shade700,
          label: 'Name',
          content: result.nameResult.isCorrect
              ? result.nameResult.comment
              : 'Correct name: ${msp.name}',
          highlight: result.nameResult.isCorrect,
        ),

        const SizedBox(height: 8),

        // Party result
        _ResultRow(
          icon: result.partyCorrect ? Icons.check : Icons.close,
          iconColor: result.partyCorrect
              ? Colors.green.shade700
              : Colors.red.shade700,
          label: 'Party',
          content: result.partyCorrect
              ? msp.party
              : 'Correct party: ${msp.party}',
          highlight: result.partyCorrect,
        ),

        const SizedBox(height: 16),

        // Info box
        _InfoBox(msp: msp),

        const SizedBox(height: 20),

        // Next button
        FilledButton.icon(
          focusNode: nextFocusNode,
          autofocus: true,
          onPressed: onNext,
          icon: const Icon(Icons.arrow_forward),
          label: const Text('Next MSP'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            textStyle: const TextStyle(fontSize: 16),
          ),
        ),

        const SizedBox(height: 8),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.content,
    required this.highlight,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String content;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: highlight ? Colors.green.shade50 : Colors.red.shade50,
        border: Border.all(
          color: highlight ? Colors.green.shade200 : Colors.red.shade200,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 10),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Expanded(child: Text(content)),
        ],
      ),
    );
  }
}

class _PartyBadge extends StatelessWidget {
  const _PartyBadge({required this.party});

  final String party;

  @override
  Widget build(BuildContext context) {
    final color = _partyColor(party);
    final textColor = _partyTextColor(party);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(40),
        border: Border.all(color: color.withAlpha(120)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        party,
        style: TextStyle(
          fontSize: 12,
          color: textColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.msp});

  final Msp msp;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F0FE),
        border: Border.all(color: const Color(0xFF90CAF9)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.info_outline,
                color: Color(0xFF1565C0),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                msp.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1565C0),
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Link(
            uri: Uri.parse(msp.profileUrl),
            target: LinkTarget.blank,
            builder: (context, followLink) => InkWell(
              onTap: followLink,
              child: Row(
                children: [
                  const Icon(
                    Icons.open_in_new,
                    size: 16,
                    color: Color(0xFF1565C0),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'View ${msp.name} on the Scottish Parliament website',
                      style: const TextStyle(
                        color: Color(0xFF1565C0),
                        decoration: TextDecoration.underline,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Completion view ───────────────────────────────────────────────────────────

class _CompleteView extends StatelessWidget {
  const _CompleteView({
    super.key,
    required this.total,
    required this.onPlayAgain,
  });

  final int total;
  final VoidCallback onPlayAgain;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 40),
        const Icon(Icons.emoji_events, size: 80, color: Color(0xFFF5D800)),
        const SizedBox(height: 20),
        Text(
          'Congratulations!',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text(
          'You have correctly identified all $total Scottish MSPs!',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: onPlayAgain,
          icon: const Icon(Icons.replay),
          label: const Text('Play Again'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            textStyle: const TextStyle(fontSize: 16),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

// ── Footer ────────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return ExcludeFocus(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        color: const Color(0xFF002060),
        child: Column(
          children: [
            _FooterLink(
              label: 'Data & images from Scottish Parliament',
              url: 'https://www.parliament.scot/',
            ),
            const SizedBox(height: 4),
            _FooterRichLine(),
          ],
        ),
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return Link(
      uri: Uri.parse(url),
      target: LinkTarget.blank,
      builder: (context, followLink) => InkWell(
        onTap: followLink,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.open_in_new, size: 13, color: Colors.white54),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withAlpha(200),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FooterRichLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: Color(0xFFB0BEC5), fontSize: 12);
    const linkStyle = TextStyle(
      color: Color(0xFF90CAF9),
      fontSize: 12,
      decoration: TextDecoration.underline,
      decorationColor: Color(0xFF90CAF9),
    );
    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        Link(
          uri: Uri.parse('https://github.com/pkeir/msp-active-recall'),
          target: LinkTarget.blank,
          builder: (context, followLink) => InkWell(
            onTap: followLink,
            child: const Text('Source code', style: linkStyle),
          ),
        ),
        const Text(' developed with the help of ', style: style),
        Link(
          uri: Uri.parse('https://code.claude.com/docs/en/cli-reference'),
          target: LinkTarget.blank,
          builder: (context, followLink) => InkWell(
            onTap: followLink,
            child: const Text('Claude CLI', style: linkStyle),
          ),
        ),
      ],
    );
  }
}
