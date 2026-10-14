import '../analysis/dart_symbol_index.dart';
import '../errors/impact_error.dart';

/// How the plan was provided by the caller.
enum PlanExtractionKind {
  structured('structured'),
  freeText('free_text');

  const PlanExtractionKind(this.jsonValue);

  final String jsonValue;
}

/// One candidate file plus optional symbols from the plan.
class PlanCandidate {
  const PlanCandidate({
    required this.path,
    this.symbols = const <String>[],
    this.exists = false,
  });

  /// Repo-relative POSIX path.
  final String path;
  final List<String> symbols;

  /// False when the path was declared in the plan but missing on disk.
  final bool exists;
}

/// Result of turning a plan (JSON or markdown) into file candidates.
class ExtractedPlan {
  const ExtractedPlan({
    required this.kind,
    required this.files,
    required this.unmatchedSymbols,
    required this.notes,
  });

  final PlanExtractionKind kind;
  final List<PlanCandidate> files;

  /// Identifiers found in the text that do not map to a known symbol.
  final List<String> unmatchedSymbols;

  /// Human-readable notes (ambiguity lowering confidence).
  final List<String> notes;

  bool get hasCandidates => files.isNotEmpty;
}

/// Extracts file/symbol candidates from structured plans or free text.
class PlanExtractor {
  const PlanExtractor(this.index);

  final DartSymbolIndex index;

  /// Parses a structured plan object: `{ title, steps[ { files, symbols } ] }`.
  ExtractedPlan fromStructured(Object? planJson) {
    if (planJson is! Map) {
      throw ImpactError(
        ImpactErrorCodes.invalidPlan,
        'plan must be a JSON object with "steps"',
      );
    }
    final map = planJson;
    final steps = map['steps'];
    if (steps is! List) {
      throw ImpactError(
        ImpactErrorCodes.invalidPlan,
        'plan "steps" must be a list',
      );
    }

    final files = <String, PlanCandidate>{};
    final notes = <String>[];
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      if (step is! Map) {
        throw ImpactError(
          ImpactErrorCodes.invalidPlan,
          'plan step $i must be an object',
        );
      }
      final stepMap = step;
      final stepFiles = stepMap['files'];
      if (stepFiles is! List) {
        throw ImpactError(
          ImpactErrorCodes.invalidPlan,
          'plan step $i is missing a "files" list',
        );
      }
      final stepSymbols = (stepMap['symbols'] as List?) ?? const <dynamic>[];

      for (final rawPath in stepFiles) {
        if (rawPath is! String) {
          throw ImpactError(
            ImpactErrorCodes.invalidPlan,
            'plan file entries must be strings',
          );
        }
        final path = rawPath.replaceAll('\\', '/');
        final exists = index.unitsByPath.containsKey(index.toAbsolute(path));
        files.putIfAbsent(
          path,
          () => PlanCandidate(
            path: path,
            symbols: stepSymbols.whereType<String>().toList(),
            exists: exists,
          ),
        );
        if (!exists) notes.add('path in plan not found on disk: $path');
      }
    }

    if (files.isEmpty) {
      throw ImpactError(
        ImpactErrorCodes.invalidPlan,
        'no file candidates found in plan',
      );
    }

    return ExtractedPlan(
      kind: PlanExtractionKind.structured,
      files: files.values.toList()..sort((a, b) => a.path.compareTo(b.path)),
      unmatchedSymbols: const <String>[],
      notes: notes,
    );
  }

  /// Parses markdown text, extracting `.dart` paths and identifier names.
  ExtractedPlan fromMarkdown(String text) {
    final files = <String, PlanCandidate>{};

    PlanCandidate existing(String path) =>
        PlanCandidate(path: path, exists: index.unitsByPath.containsKey(index.toAbsolute(path)));

    for (final match in RegExp(r'[A-Za-z0-9_./\\-]+\.dart').allMatches(text)) {
      final path = match.group(0)!.replaceAll('\\', '/');
      files.putIfAbsent(path, () => existing(path));
    }

    final unmatchedSymbols = <String>{};
    for (final match in RegExp(r'`([A-Za-z_$][\w$]*)`').allMatches(text)) {
      final name = match.group(1)!;
      final symbols = index.symbolsByName[name];
      if (symbols == null || symbols.isEmpty) {
        unmatchedSymbols.add(name);
        continue;
      }
      for (final symbol in symbols) {
        final relative = index.toRelative(symbol.file);
        files.putIfAbsent(relative, () => PlanCandidate(path: relative, symbols: [name], exists: true));
      }
    }

    if (files.isEmpty) {
      throw ImpactError(
        ImpactErrorCodes.invalidPlan,
        'no file candidates found in plan text',
      );
    }

    return ExtractedPlan(
      kind: PlanExtractionKind.freeText,
      files: files.values.toList()..sort((a, b) => a.path.compareTo(b.path)),
      unmatchedSymbols: unmatchedSymbols.toList()..sort(),
      notes: <String>[
        if (unmatchedSymbols.isNotEmpty)
          'unresolved identifiers: ${unmatchedSymbols.join(', ')}',
      ],
    );
  }
}
