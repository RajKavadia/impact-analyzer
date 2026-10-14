import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:path/path.dart' as p;

import '../ignore/ignore_rules.dart';

/// The shape of a declared Dart symbol.
enum SymbolKind {
  classType('class'),
  enumType('enum'),
  mixin('mixin'),
  extension('extension'),
  typedef('typedef'),
  function('function'),
  variable('variable');

  const SymbolKind(this.jsonValue);

  final String jsonValue;
}

/// A symbol declared in a Dart file.
class DeclaredSymbol {
  const DeclaredSymbol({
    required this.file,
    required this.name,
    required this.kind,
    this.enclosing,
    this.isPublic = true,
    this.supertypeNames = const <String>[],
    this.offset,
  });

  /// Absolute POSIX path of the declaring file.
  final String file;
  final String name;
  final SymbolKind kind;

  /// Enclosing type name for members, `null` for top-level declarations.
  final String? enclosing;
  final bool isPublic;

  /// Names of known supertypes (used for Flutter UI root detection).
  final List<String> supertypeNames;

  /// Source offset of the declaration name, when the analyzer resolved it.
  ///
  /// Used to attribute a reference to the type that encloses it. `null` in
  /// regex fallback mode.
  final int? offset;

  bool get isTopLevel => enclosing == null;

  bool get isTypeKind =>
      kind == SymbolKind.classType ||
      kind == SymbolKind.enumType ||
      kind == SymbolKind.mixin ||
      kind == SymbolKind.extension ||
      kind == SymbolKind.typedef;

  /// `file#Name` for top-level declarations, `file#Type.member` for members.
  String get key => enclosing == null ? '$file#$name' : '$file#$enclosing.$name';

  /// `file#Name` or `file#Type` - the declaration a member belongs to.
  String get topLevelKey =>
      enclosing == null ? '$file#$name' : '$file#$enclosing';
}

/// A resolved identifier occurrence in a file.
class SymbolReference {
  const SymbolReference({
    required this.file,
    required this.keys,
    this.offset,
  });

  final String file;

  /// Candidate changed-symbol keys this occurrence could match.
  final Set<String> keys;

  /// Source offset of the occurrence, used to find the enclosing type.
  final int? offset;
}

/// Per-file analysis facts used to build the impact graph.
class FileUnit {
  const FileUnit({
    required this.path,
    required this.library,
    required this.imports,
    required this.declarations,
    required this.references,
    required this.resolved,
  });

  /// Absolute POSIX file path.
  final String path;

  /// Absolute POSIX path of the library this file belongs to (parts included).
  final String library;

  /// Absolute POSIX paths of libraries this file imports/exports.
  final Set<String> imports;

  final List<DeclaredSymbol> declarations;
  final List<SymbolReference> references;

  /// False when the analyzer could not resolve the file (warnings recorded).
  final bool resolved;
}

/// Analyzer-backed index of declarations, imports and references.
///
/// All internal paths are absolute POSIX. When no `package_config.json` is
/// available the index degrades to regex scanning and [fallback] is true.
class DartSymbolIndex {
  const DartSymbolIndex._({
    required this.repoRoot,
    required this.unitsByPath,
    required this.symbolsByKey,
    required this.symbolsByName,
    required this.fallback,
    required this.warnings,
  });

  final String repoRoot;
  final Map<String, FileUnit> unitsByPath;

  /// Key (`file#Name`) to symbol, for top-level declarations and members.
  final Map<String, DeclaredSymbol> symbolsByKey;

  /// Symbol name to declarations (plan extraction, MCP queries).
  final Map<String, List<DeclaredSymbol>> symbolsByName;

  final bool fallback;
  final List<String> warnings;

  int get analyzedFileCount => unitsByPath.length;

  /// Looks up a file unit by absolute **or** repo-relative path.
  FileUnit? unitOf(String path) => unitsByPath[toAbsolute(path)];

  Iterable<DeclaredSymbol> get allSymbols => symbolsByKey.values;

  /// Every name declared anywhere in the repository (sorted).
  Iterable<String> get allNames {
    final names = symbolsByName.keys.toList()..sort();
    return names;
  }

  /// Converts an absolute or repo-relative path to an absolute POSIX path.
  ///
  /// Already-absolute inputs are returned as-is (normalized), never re-joined
  /// onto the repo root.
  String toAbsolute(String path) {
    final raw = _looksAbsolute(path)
        ? path
        : p.join(repoRoot, p.split(path).join(p.separator));
    return _normalizePath(p.normalize(raw));
  }

  /// Converts an absolute or repo-relative path to a repo-relative POSIX path.
  String toRelative(String path) {
    final absolute = toAbsolute(path);
    return _normalizePath(
      p.relative(p.joinAll(absolute.split('/')), from: p.joinAll(repoRoot.split('/'))),
    );
  }

  /// True when the file is public API: under `lib/`, outside `src/`, non-private.
  bool isPublicApiSymbol(DeclaredSymbol symbol) {
    final relative = toRelative(symbol.file);
    if (!relative.startsWith('lib/')) return false;
    if (p.split(relative).contains('src')) return false;
    return !symbol.name.startsWith('_');
  }

  /// True when the type matches a configured Flutter/state root type.
  bool isFlutterRootType(DeclaredSymbol symbol, List<String> roots) {
    if (roots.isEmpty) return false;
    if (roots.contains(symbol.name)) return true;
    final enclosing = symbol.enclosing;
    if (enclosing != null && roots.contains(enclosing)) return true;
    return symbol.supertypeNames.any(roots.contains);
  }

  static Future<DartSymbolIndex> build({
    required String repoRoot,
    required IgnoreRules ignoreRules,
  }) async {
    final repoRootNative = p.absolute(repoRoot);
    final repoRootPosix = _normalizePath(repoRootNative);
    final files = _listDartFiles(repoRootNative, ignoreRules);
    final includePaths = _analysisIncludePaths(repoRootNative, ignoreRules);
    final hasPackageConfig = includePaths.any(
      (dir) => File(p.join(dir, '.dart_tool', 'package_config.json')).existsSync(),
    );

    final unitsByPath = <String, FileUnit>{};
    final warnings = <String>[];
    final fallback = !hasPackageConfig;

    if (!fallback) {
      final collection = AnalysisContextCollection(
        includedPaths: includePaths,
        resourceProvider: PhysicalResourceProvider.INSTANCE,
      );
      for (final file in files) {
        FileUnit? unit;
        try {
          final nativeFile = p.joinAll(file.split('/'));
          final session = collection.contextFor(nativeFile).currentSession;
          final result = await session.getResolvedUnit(nativeFile);
          if (result is ResolvedUnitResult && result.exists) {
            unit = _unitFromResult(result, file, warnings);
          }
        } on Object catch (e) {
          warnings.add('failed to resolve ${_basename(file)}: $e');
        }
        if (unit == null) {
          warnings.add('analyzer could not fully resolve ${_basename(file)}');
          unit = _unitFromFileFallback(file);
        }
        unitsByPath[file] = unit;
      }
    } else {
      final symbols = <DeclaredSymbol>[];
      for (final file in files) {
        final posixFile = _normalizePath(file);
        final unit = _unitFromFileFallback(posixFile);
        unitsByPath[posixFile] = unit;
        symbols.addAll(unit.declarations);
      }
      // Name-based reference scan (coarse; callers lower confidence).
      final names = symbols.map((s) => s.name).toSet();
      for (final path in unitsByPath.keys.toList()) {
        final unit = unitsByPath[path]!;
        final content = File(path).readAsStringSync();
        final keys = <String>{};
        for (final name in names) {
          if (!RegExp(r'\b' + RegExp.escape(name) + r'\b').hasMatch(content)) continue;
          keys.addAll(symbols.where((s) => s.name == name).map((s) => s.key));
        }
        unitsByPath[path] = FileUnit(
          path: unit.path,
          library: unit.library,
          imports: unit.imports,
          declarations: unit.declarations,
          references: [
            if (keys.isNotEmpty) SymbolReference(file: path, keys: keys),
          ],
          resolved: false,
        );
      }
    }

    final symbolsByKey = <String, DeclaredSymbol>{};
    final symbolsByName = <String, List<DeclaredSymbol>>{};
    for (final unit in unitsByPath.values) {
      for (final symbol in unit.declarations) {
        symbolsByKey.putIfAbsent(symbol.key, () => symbol);
        symbolsByName.putIfAbsent(symbol.name, () => <DeclaredSymbol>[]).add(symbol);
      }
    }
    for (final names in symbolsByName.values) {
      names.sort((a, b) => a.file.compareTo(b.file));
    }

    return DartSymbolIndex._(
      repoRoot: repoRootPosix,
      unitsByPath: unitsByPath,
      symbolsByKey: symbolsByKey,
      symbolsByName: symbolsByName,
      fallback: fallback,
      warnings: warnings,
    );
  }

  static FileUnit _unitFromResult(
    ResolvedUnitResult result,
    String file,
    List<String> warnings,
  ) {
    final unit = result.unit;
    final libraryElement = result.libraryElement;
    final libraryFragment = result.libraryFragment;
    final libraryPath = _normalizePath(libraryElement.firstFragment.source.fullName);

    final imports = <String>{};
    for (final imported in libraryFragment.importedLibraries) {
      final source = imported.firstFragment.source;
      if (source.fullName.isNotEmpty) {
        imports.add(_normalizePath(source.fullName));
      }
    }

    final declarations = <DeclaredSymbol>[];
    _collectElementDeclarations(libraryElement, libraryPath, declarations);

    final collector = _ReferenceCollector(file);
    collector.collect(unit);

    return FileUnit(
      path: file,
      library: libraryPath,
      imports: imports,
      declarations: _dedupeByKey(declarations),
      references: collector.references,
      resolved: true,
    );
  }

  /// Collapses the field/getter/setter trio, which the element model reports as
  /// separate members that all map to the same `file#Type.name` key.
  ///
  /// The first occurrence wins so the richest record (a field carries the
  /// declaring offset) is preserved when available.
  static List<DeclaredSymbol> _dedupeByKey(List<DeclaredSymbol> symbols) {
    final byKey = <String, DeclaredSymbol>{};
    for (final symbol in symbols) {
      final existing = byKey[symbol.key];
      if (existing == null || (existing.offset == null && symbol.offset != null)) {
        byKey[symbol.key] = symbol;
      }
    }
    return byKey.values.toList();
  }

  static void _collectElementDeclarations(
    LibraryElement library,
    String libraryPath,
    List<DeclaredSymbol> declarations,
  ) {
    void add(
      String? name,
      SymbolKind kind, {
      String? enclosing,
      List<String> supertypes = const <String>[],
      int? offset,
    }) {
      if (name == null || name.isEmpty || name == 'new') return;
      declarations.add(DeclaredSymbol(
        file: libraryPath,
        name: name,
        kind: kind,
        enclosing: enclosing,
        isPublic: !name.startsWith('_'),
        supertypeNames: supertypes,
        offset: offset,
      ));
    }

    int? nameOffsetOf(Element element) =>
        element.firstFragment.nameOffset;

    for (final element in library.classes) {
      add(element.name, SymbolKind.classType,
          supertypes: _supertypeNames(element), offset: nameOffsetOf(element));
      _collectMembers(element, libraryPath, declarations);
    }
    for (final element in library.enums) {
      add(element.name, SymbolKind.enumType, offset: nameOffsetOf(element));
    }
    for (final element in library.mixins) {
      add(element.name, SymbolKind.mixin,
          supertypes: _supertypeNames(element), offset: nameOffsetOf(element));
      _collectMembers(element, libraryPath, declarations);
    }
    for (final element in library.extensions) {
      add(element.name, SymbolKind.extension, offset: nameOffsetOf(element));
      _collectExtensionMembers(element, libraryPath, declarations);
    }
    for (final element in library.extensionTypes) {
      add(element.name, SymbolKind.classType, offset: nameOffsetOf(element));
      _collectMembers(element, libraryPath, declarations);
    }
    for (final element in library.typeAliases) {
      add(element.name, SymbolKind.typedef, offset: nameOffsetOf(element));
    }
    for (final element in library.topLevelFunctions) {
      add(element.name, SymbolKind.function, offset: nameOffsetOf(element));
    }
    for (final element in library.topLevelVariables) {
      add(element.name, SymbolKind.variable, offset: nameOffsetOf(element));
    }
  }

  /// Extension members live on the extension fragment rather than the element.
  static void _collectExtensionMembers(
    ExtensionElement element,
    String libraryPath,
    List<DeclaredSymbol> declarations,
  ) {
    final typeName = element.name;
    if (typeName == null || typeName.isEmpty) return;

    void add(String? name, SymbolKind kind) {
      if (name == null || name.isEmpty || name == 'new') return;
      if (name.startsWith('_')) return;
      declarations.add(DeclaredSymbol(
        file: libraryPath,
        name: name,
        kind: kind,
        enclosing: typeName,
        isPublic: true,
      ));
    }

    for (final method in element.methods) {
      add(method.name, SymbolKind.function);
    }
    for (final getter in element.getters) {
      add(getter.name, SymbolKind.function);
    }
    for (final setter in element.setters) {
      add(setter.name, SymbolKind.function);
    }
    for (final field in element.fields) {
      add(field.name, SymbolKind.variable);
    }
  }

  static void _collectMembers(
    InterfaceElement element,
    String libraryPath,
    List<DeclaredSymbol> declarations,
  ) {
    final typeName = element.name;
    if (typeName == null || typeName.isEmpty) return;

    void add(String? name, SymbolKind kind) {
      if (name == null || name.isEmpty || name == 'new') return;
      declarations.add(DeclaredSymbol(
        file: libraryPath,
        name: name,
        kind: kind,
        enclosing: typeName,
        isPublic: !name.startsWith('_'),
      ));
    }

    for (final field in element.fields) {
      add(field.name, SymbolKind.variable);
    }
    for (final getter in element.getters) {
      add(getter.name, SymbolKind.function);
    }
    for (final setter in element.setters) {
      add(setter.name, SymbolKind.function);
    }
    for (final method in element.methods) {
      add(method.name, SymbolKind.function);
    }
  }

  static List<String> _supertypeNames(InterfaceElement element) {
    final names = <String>[];
    for (final type in element.allSupertypes) {
      final name = type.element.name;
      if (name != null && name.isNotEmpty) names.add(name);
    }
    return names;
  }

  /// Regex-based unit used when the analyzer cannot resolve the project.
  static FileUnit _unitFromFileFallback(String file) {
    final content = File(file).readAsStringSync();

    final imports = <String>{};
    for (final match in RegExp(r"^\s*(?:import|export)\s+'([^']+)'", multiLine: true)
        .allMatches(content)) {
      final resolved = _resolveImportUri(match.group(1)!, file);
      if (resolved != null) imports.add(resolved);
    }

    final declarations = <DeclaredSymbol>[];
    void add(String name, SymbolKind kind) {
      declarations.add(DeclaredSymbol(
        file: file,
        name: name,
        kind: kind,
        isPublic: !name.startsWith('_'),
      ));
    }

    const patterns = <(String, SymbolKind)>[
      (r'^(?:abstract\s+|base\s+|interface\s+|final\s+|sealed\s+|mixin\s+)*class\s+([A-Za-z_$][\w$]*)',
          SymbolKind.classType),
      (r'^mixin\s+([A-Za-z_$][\w$]*)', SymbolKind.mixin),
      (r'^enum\s+([A-Za-z_$][\w$]*)', SymbolKind.enumType),
      (r'^extension\s+([A-Za-z_$][\w$]*)', SymbolKind.extension),
      (r'^typedef\s+([A-Za-z_$][\w$]*)', SymbolKind.typedef),
      (r'^(?:const\s+|final\s+|var\s+)[A-Za-z_$<>,\s]*?\s([a-z_][\w$]*)\s*=',
          SymbolKind.variable),
    ];
    for (final (pattern, kind) in patterns) {
      for (final match in RegExp(pattern, multiLine: true).allMatches(content)) {
        add(match.group(1)!, kind);
      }
    }
    final functionPattern = RegExp(
      r'^(?:[A-Za-z_$][\w$<>,\s]*?\s+)?([a-zA-Z_][\w$]*)\s*\(',
      multiLine: true,
    );
    for (final match in functionPattern.allMatches(content)) {
      final name = match.group(1)!;
      if (name == 'if' || name == 'for' || name == 'while' || name == 'switch') {
        continue;
      }
      add(name, SymbolKind.function);
    }

    return FileUnit(
      path: file,
      library: file,
      imports: imports,
      declarations: _dedupeByKey(declarations),
      references: const <SymbolReference>[],
      resolved: false,
    );
  }

  static String? _resolveImportUri(String uri, String importingFile) {
    if (uri.startsWith('dart:')) return null;
    if (uri.startsWith('package:')) {
      final configFile = File(p.join(
        _normalizePath(p.dirname(importingFile)),
        '.dart_tool',
        'package_config.json',
      ));
      if (!configFile.existsSync()) return null;
      try {
        final config =
            jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
        final packages = config['packages'] as List<dynamic>;
        final rest = uri.substring('package:'.length);
        final slash = rest.indexOf('/');
        if (slash < 0) return null;
        final packageName = rest.substring(0, slash);
        final configDir = Uri.directory(configFile.parent.path);
        for (final entry in packages) {
          final map = entry as Map<String, dynamic>;
          if (map['name'] != packageName) continue;
          final rootUri = Uri.parse(map['rootUri'] as String);
          final packageUri = Uri.parse((map['packageUri'] as String?) ?? 'lib/');
          final target = configDir
              .resolveUri(rootUri)
              .resolveUri(packageUri)
              .resolve(rest.substring(slash + 1));
          return _normalizePath(Uri.decodeComponent(target.toFilePath()));
        }
      } on Object {
        return null;
      }
      return null;
    }
    return _normalizePath(p.normalize(p.join(p.dirname(importingFile), uri)));
  }
}

/// Walks a resolved unit and records identifier/type references to top-level
/// declarations (types, top-level functions/variables, and their members).
///
/// The analyzer's V1 visitor methods are not dispatched by the current AST
/// implementation, so this walks the node tree directly via `visitChildren`
/// and resolves elements from each node.
class _ReferenceCollector {
  _ReferenceCollector(this.filePath);

  final String filePath;
  final List<SymbolReference> references = [];

  void collect(CompilationUnit unit) {
    unit.accept(_ChildWalker(this));
  }

  static void _record(
    _ReferenceCollector owner,
    Element? element,
    int? offset,
  ) {
    if (element == null) return;
    final keys = _keysFor(element);
    if (keys.isEmpty) return;
    owner.references.add(SymbolReference(
      file: owner.filePath,
      keys: keys,
      offset: offset,
    ));
  }

  static Set<String> _keysFor(Element element) {
    if (element is PrefixElement ||
        element is LibraryElement ||
        element is FormalParameterElement ||
        element is LocalVariableElement ||
        element is LabelElement ||
        element is LocalFunctionElement) {
      return const <String>{};
    }

    if (element is PropertyAccessorElement) {
      final variable = element.variable;
      if (variable is TopLevelVariableElement) {
        final key = _keyOf(variable);
        return key == null ? const <String>{} : <String>{key};
      }
      final top = _enclosingTopLevel(variable);
      if (top == null) return const <String>{};
      return _keysForPair(top, element);
    }

    final top = _enclosingTopLevel(element);
    if (top == null) return const <String>{};
    return _keysForPair(top, element);
  }

  static Set<String> _keysForPair(Element topLevel, Element reference) {
    final topKey = _keyOf(topLevel);
    final memberKey = identical(topLevel, reference) ? null : _memberKey(topLevel, reference);
    final keys = <String>{};
    if (topKey != null) keys.add(topKey);
    if (memberKey != null) keys.add(memberKey);
    return keys;
  }

  static Element? _enclosingTopLevel(Element element) {
    Element current = element;
    while (true) {
      final parent = current.enclosingElement;
      if (parent == null || parent is LibraryElement) {
        break;
      }
      current = parent;
    }
    return current;
  }

  static String? _keyOf(Element topLevel) {
    final name = topLevel.name;
    if (name == null || name.isEmpty) return null;
    final library = topLevel.library;
    if (library == null) return null;
    return '${_normalizePath(library.firstFragment.source.fullName)}#$name';
  }

  static String? _memberKey(Element topLevel, Element member) {
    final topName = topLevel.name;
    final memberName = member.name;
    if (topName == null || topName.isEmpty) return null;
    if (memberName == null || memberName.isEmpty || memberName == 'new') return null;
    final library = topLevel.library;
    if (library == null) return null;
    return '${_normalizePath(library.firstFragment.source.fullName)}#$topName.$memberName';
  }
}

/// Collects resolved references from a compilation unit.
class _ChildWalker extends RecursiveAstVisitor<void> {
  _ChildWalker(this.owner);

  final _ReferenceCollector owner;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    _ReferenceCollector._record(owner, node.element, node.offset);
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitNamedType(NamedType node) {
    _ReferenceCollector._record(owner, node.element, node.offset);
    super.visitNamedType(node);
  }
}

/// Matches POSIX (`/x`), Windows drive (`C:/x`) and UNC (`//host/x`) paths.
///
/// Platform independent on purpose: the index stores posix paths even when the
/// host platform uses different separators.
final RegExp _absolutePattern = RegExp(r'^(?:[A-Za-z]:[/\\]|[/\\]{1,2}[^/\\])');

bool _looksAbsolute(String path) => _absolutePattern.hasMatch(path);

/// Normalizes a file path to absolute POSIX format consistently across platforms.
String _normalizePath(String path) {
  var normalized = path.replaceAll('\\', '/');
  while (normalized.contains('//')) {
    normalized = normalized.replaceAll('//', '/');
  }
  if (Platform.isWindows && RegExp(r'^/[A-Za-z]:').hasMatch(normalized)) {
    normalized = normalized.substring(1);
  }
  return normalized;
}

String _basename(String path) => p.basename(path);

List<String> _listDartFiles(String repoRoot, IgnoreRules ignoreRules) {
  final files = <String>[];

  void walk(Directory dir) {
    final entries = dir.listSync(followLinks: false);
    entries.sort((a, b) => a.path.compareTo(b.path));
    for (final entity in entries) {
      if (ignoreRules.isIgnored(entity.path, repoRoot: repoRoot)) continue;
      if (entity is Directory) {
        walk(entity);
      } else if (entity is File && entity.path.endsWith('.dart')) {
        files.add(_normalizePath(entity.path));
      }
    }
  }

  walk(Directory(repoRoot));
  files.sort();
  return files;
}

/// Directories whose `.dart_tool/package_config.json` drives resolution.
List<String> _analysisIncludePaths(String repoRoot, IgnoreRules ignoreRules) {
  final roots = <String>[repoRoot];

  void walk(Directory dir, int depth) {
    if (depth > 4) return;
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is! Directory) continue;
      if (ignoreRules.isIgnored(entity.path, repoRoot: repoRoot)) continue;
      if (File(p.join(entity.path, 'pubspec.yaml')).existsSync()) {
        roots.add(p.absolute(entity.path));
      }
      walk(entity, depth + 1);
    }
  }

  walk(Directory(repoRoot), 0);
  roots.sort();
  return roots;
}