/// Pure CNL completion engine — no Flutter imports, fully unit-testable.
///
/// Provides three layers of completion for the CNL editor:
///
/// 1. **Template completions** — existing behaviour, moved here from
///    `cnl_editor.dart`. Full-line prefix matching against the canonical
///    template library. Returns up to [max] matching template strings
///    (including `{slot}` markers).
///
/// 2. **Token completions** — new. When the full-line prefix does not match
///    any template, try completing the *last partial token* on the line against
///    the CNL keyword, verb, unit, and adjective vocabularies. Returns plain
///    token strings (no slot markers).
///
/// 3. **Node-name completions** — new. When the cursor follows a
///    subject-position keyword (`The`, `A`, `from`, `to`, `by`), offer the
///    canvas node labels as completions for the partial token being typed.
///    Returns node-label strings prefixed with a canonical-name marker so the
///    overlay can badge them differently.
library;

/// Source category of a completion item — used for the badge in the overlay.
enum CompletionSource {
  /// A full sentence template with `{slot}` markers.
  template,

  /// A single CNL keyword, verb, unit, or adjective.
  token,

  /// A node label drawn from the live canvas.
  node,
}

/// A single completion suggestion.
class CompletionItem {
  const CompletionItem({required this.text, required this.source});

  /// The text to insert (or display in the overlay).
  final String text;

  /// Origin of this suggestion.
  final CompletionSource source;

  @override
  String toString() => 'CompletionItem($source, $text)';
}

// ── CNL vocabulary ────────────────────────────────────────────────────────────

const List<String> _kKeywords = <String>[
  'MUST NOT',
  'MUST',
  'ONLY IF',
  'IF',
  'WITH',
  'DURING',
  'AFTER',
  'WITHIN',
  'BETWEEN',
  'AND',
  'BY',
];

const List<String> _kVerbs = <String>[
  'exceeds',
  'fire',
  'emit',
  'strengthen',
  'weaken',
  'modulate',
  'decay',
  'adapt',
  'contain',
  'project',
  'inhibit',
  'maintain',
  'represent',
  'encode',
  'respond to',
];

const List<String> _kUnits = <String>['seconds', 'ms', 'Hz', 'degrees'];

const List<String> _kAdjectives = <String>[
  'inhibitory',
  'excitatory',
  'plastic',
  'active',
  'inactive',
  'membrane potential',
  'refractory period',
  'synaptic weight',
  'axonal delay',
];

/// Words after which the next token is likely a subject or object name
/// (node label from the canvas).
const List<String> _kSubjectPositionWords = <String>[
  'the',
  'a',
  'an',
  'from',
  'to',
  'by',
];

// ── Template library — canonical CNL sentence templates ─────────────────────

/// All valid CNL sentence templates. `cnl_editor.dart` previously duplicated
/// this list; it now delegates entirely to this engine.
const List<String> kAllCnlTemplates = <String>[
  // 1 — Threshold Firing
  'The {neuron} MUST fire ONLY IF membrane potential exceeds {1.0}',
  'The {neuron} MUST NOT fire ONLY IF membrane potential exceeds {1.0}',
  'The {neuron} MUST emit a spike ONLY IF membrane potential exceeds {0.5}',
  'A {neuron} MUST fire ONLY IF membrane potential exceeds {1.0}',
  // 2 — Refractory Period
  'The {neuron} MUST NOT fire DURING the refractory period of {0.002} seconds',
  'The {neuron} MUST NOT respond to input DURING the refractory period',
  'The {neuron} MUST remain inactive AFTER firing for {0.002} seconds',
  // 3 — Membrane Potential Decay
  'The {neuron} membrane potential MUST decay WITH time constant of {0.02} seconds',
  'The {neuron} membrane potential MUST NOT increase WITHOUT input',
  // 4 — Synaptic Weight
  'The connection from {source neuron} to {target neuron} MUST have WITH synaptic weight of {1.0}',
  'The connection from {source neuron} to {target neuron} MUST transmit WITH synaptic weight of {0.5}',
  'The connection from {source neuron} to {target neuron} MUST NOT have WITH synaptic weight of {0.0}',
  // 5 — Axonal Delay
  'A synapse MUST have a transmission delay of {5} ms',
  'A synapse MUST have a transmission delay of {0.005} seconds',
  'The connection from {source neuron} to {target neuron} MUST transmit WITH delay of {3} ms',
  // 6 — STDP Learning
  'A synapse MUST strengthen IF pre-synaptic spike precedes post-synaptic spike by less than {20} ms',
  'A synapse MUST weaken IF post-synaptic spike precedes pre-synaptic spike',
  'A synapse MUST NOT have weights exceeding {2.0}',
  'The connection from {source} to {target} MUST adapt WITH STDP learning rate of {0.01}',
  'The connection from {source} to {target} MUST strengthen IF pre fires before post WITHIN {20} ms',
  'The connection from {source} to {target} MUST weaken IF post fires before pre WITHIN {50} ms',
  'The connection from {source} to {target} MUST maintain weight BETWEEN {0.1} AND {1.5}',
  'The connection from {source} to {target} MUST adapt WITH BCM learning rate of {0.001}',
  'The connection from {source} to {target} MUST adapt WITH Oja learning rate of {0.001}',
  // 7 — Inhibitory Connection
  'The connection from {interneuron} to {motor neuron} MUST be inhibitory',
  'The connection from {interneuron} to {motor neuron} MUST be inhibitory with weight of {-0.5}',
  // 8 — Population Coding
  'The {sensory population} MUST encode input using {100} neurons',
  'The {motor ensemble} MUST represent values in range {-1} to {1}',
  'The {sensory population} MUST encode input using {50} neurons with {2} dimensions',
  // 9 — Network Topology
  'The network MUST contain an inhibitory {interneuron} population of {30} neurons',
  'The network MUST contain an excitatory {relay} population of {50} neurons',
  'The {sensory neuron} MUST project to both {motor neuron} AND {interneuron}',
  // 10 — Lateral Inhibition
  'The {sensory neuron} MUST inhibit neighboring neurons WITHIN radius of {2}',
  // 11 — Homeostatic Plasticity
  'The {sensory neuron} MUST maintain average firing rate of {10} Hz',
  // 12 — Neuromodulation
  '{Dopamine} MUST modulate synaptic weight BY factor of {1.5}',
  '{Serotonin} MUST modulate synaptic weight BY factor of {0.8}',
  // 13 — Population Coding Range
  'The {population} MUST encode stimulus {orientation} WITH {360} degree range',
];

/// Strip `{slot}` markers so prefix matching works on plain text.
/// e.g. `'The {neuron} MUST fire…'` → `'The neuron MUST fire…'`
final List<String> _kTemplateMatchKeys = kAllCnlTemplates
    .map(
      (String t) =>
          t.replaceAllMapped(RegExp(r'\{([^}]*)\}'), (Match m) => m.group(1)!),
    )
    .toList(growable: false);

// ── Engine ────────────────────────────────────────────────────────────────────

/// Pure completion engine — no Flutter / Riverpod / platform dependencies.
class CnlCompletionEngine {
  const CnlCompletionEngine();

  // ── Layer 1: template completions ─────────────────────────────────────────

  /// Returns template completions whose stripped match key starts with
  /// [linePrefix] (case-insensitive). Up to [max] results.
  List<CompletionItem> templateCompletions(String linePrefix, {int max = 10}) {
    if (linePrefix.trimLeft().length < 2) return const <CompletionItem>[];
    final String prefix = linePrefix.toLowerCase();
    final results = <CompletionItem>[];
    for (int i = 0; i < kAllCnlTemplates.length; i++) {
      if (_kTemplateMatchKeys[i].toLowerCase().startsWith(prefix)) {
        results.add(
          CompletionItem(
            text: kAllCnlTemplates[i],
            source: CompletionSource.template,
          ),
        );
        if (results.length >= max) break;
      }
    }
    return results;
  }

  // ── Layer 2: token completions ────────────────────────────────────────────

  /// Returns CNL keyword/verb/unit/adjective completions that start with
  /// [partialToken] (case-insensitive). Up to [max] results.
  ///
  /// Keywords are checked case-sensitively for display (e.g. `MUST`) but
  /// matched case-insensitively.
  List<CompletionItem> tokenCompletions(String partialToken, {int max = 8}) {
    final String query = partialToken.trim().toLowerCase();
    if (query.isEmpty) return const <CompletionItem>[];

    final results = <CompletionItem>[];
    final seen = <String>{};

    void addToken(String token) {
      if (seen.add(token) && results.length < max) {
        results.add(
          CompletionItem(text: token, source: CompletionSource.token),
        );
      }
    }

    for (final String kw in _kKeywords) {
      if (kw.toLowerCase().startsWith(query)) addToken(kw);
    }
    for (final String v in _kVerbs) {
      if (v.toLowerCase().startsWith(query)) addToken(v);
    }
    for (final String u in _kUnits) {
      if (u.toLowerCase().startsWith(query)) addToken(u);
    }
    for (final String adj in _kAdjectives) {
      if (adj.toLowerCase().startsWith(query)) addToken(adj);
    }
    return results;
  }

  // ── Layer 3: node-name completions ────────────────────────────────────────

  /// Returns node-label completions from [nodeLabels] for [partialToken].
  ///
  /// A node-name completion is offered when the [precedingWord] (the last
  /// completed word before the current partial token) is a subject-position
  /// keyword such as `the`, `a`, `from`, `to`, `by`.
  ///
  /// Matching is prefix then substring, case-insensitive, up to [max] results.
  List<CompletionItem> nodeNameCompletions(
    String partialToken,
    String precedingWord,
    Iterable<String> nodeLabels, {
    int max = 5,
  }) {
    final String pw = precedingWord.trim().toLowerCase();
    if (!_kSubjectPositionWords.contains(pw)) return const <CompletionItem>[];

    final String query = partialToken.trim().toLowerCase();
    final results = <CompletionItem>[];
    final seen = <String>{};

    void addLabel(String label) {
      if (seen.add(label) && results.length < max) {
        results.add(CompletionItem(text: label, source: CompletionSource.node));
      }
    }

    // Prefix pass
    for (final String label in nodeLabels) {
      if (label.toLowerCase().startsWith(query)) addLabel(label);
    }
    // Substring pass (if still room)
    for (final String label in nodeLabels) {
      if (label.toLowerCase().contains(query) &&
          !label.toLowerCase().startsWith(query)) {
        addLabel(label);
      }
    }
    return results;
  }

  // ── Combined: unified suggestions for the current line state ─────────────

  /// Main entry point. Analyses [text] and [cursorPos] to decide which layer
  /// to invoke, then merges results into a single ordered list:
  ///
  /// 1. Template completions (if line prefix matches ≥ 1 template).
  /// 2. Token completions for the partial last word.
  /// 3. Node-name completions (if the preceding word is a subject position).
  ///
  /// Layers 2 and 3 are only used when layer 1 returns nothing.
  ///
  /// [nodeLabels] may be empty when the canvas has no nodes.
  List<CompletionItem> suggest(
    String text,
    int cursorPos,
    Iterable<String> nodeLabels, {
    int maxTemplates = 10,
    int maxTokens = 8,
    int maxNodes = 5,
  }) {
    if (cursorPos < 0 || cursorPos > text.length) {
      return const <CompletionItem>[];
    }

    final String beforeCursor = text.substring(0, cursorPos);
    final int lineStart = beforeCursor.lastIndexOf('\n') + 1;
    final String lineUpToCursor = beforeCursor.substring(lineStart);

    if (lineUpToCursor.trimLeft().length < 2) return const <CompletionItem>[];

    // Layer 1 — template
    final List<CompletionItem> templates = templateCompletions(
      lineUpToCursor,
      max: maxTemplates,
    );
    if (templates.isNotEmpty) return templates;

    // Extract partial last token and the word before it
    final List<String> words = lineUpToCursor.trimRight().split(RegExp(r'\s+'));
    final String partialToken = words.isEmpty ? '' : words.last;
    final String precedingWord = words.length >= 2
        ? words[words.length - 2]
        : '';

    final results = <CompletionItem>[];

    // Layer 2 — token keywords/verbs/units
    results.addAll(tokenCompletions(partialToken, max: maxTokens));

    // Layer 3 — node names (only if preceding word is a subject position)
    results.addAll(
      nodeNameCompletions(
        partialToken,
        precedingWord,
        nodeLabels,
        max: maxNodes,
      ),
    );

    return results;
  }
}
