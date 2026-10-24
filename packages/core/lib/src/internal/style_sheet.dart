import 'package:csslib/parser.dart' as css;
import 'package:csslib/visitor.dart' as css;
import 'package:flutter/widgets.dart';
import 'package:html/dom.dart' as dom;

import '../material_theme.dart';

// https://drafts.csswg.org/mediaqueries/#units
const _mediaFontSize = 16.0;

/// Declarations of the document `STYLE` elements, matched to their elements.
class DocumentStyleSheet {
  final _matches = <dom.Element, List<_Match>>{};

  DocumentStyleSheet._();

  /// Returns the declarations matching [element], in cascade order.
  List<css.Declaration> operator [](dom.Element element) {
    final matches = _matches[element];
    if (matches == null) {
      return const [];
    }

    matches.sort(_Match.compare);
    return [for (final match in matches) ...match.declarations];
  }

  /// Parses the `STYLE` elements found in [domNodes].
  ///
  /// Returns `null` if there is no rule to apply.
  static DocumentStyleSheet? tryParse(dom.NodeList domNodes, CssMedia media) {
    final root = domNodes.isEmpty ? null : domNodes.first.parentNode;
    if (root is! dom.DocumentFragment) {
      return null;
    }

    final styleSheet = DocumentStyleSheet._();
    var order = 0;

    void addRuleSet(css.RuleSet ruleSet) {
      final declarations = ruleSet.declarationGroup.declarations
          .whereType<css.Declaration>()
          .toList(growable: false);
      if (declarations.isEmpty) {
        return;
      }

      order++;
      final selectors = ruleSet.selectorGroup?.selectors ?? const [];
      for (final selector in selectors) {
        final text = selector.span?.text;
        final elements = text != null ? _querySelectorAll(root, text) : null;
        if (elements == null || elements.isEmpty) {
          continue;
        }

        final match = _Match(_specificity(selector), order, declarations);
        for (final element in elements) {
          final list = styleSheet._matches[element] ??= [];
          if (list.isNotEmpty && list.last.order == order) {
            // another selector of the same rule, keep the highest specificity
            if (list.last.specificity < match.specificity) {
              list.last = match;
            }
          } else {
            list.add(match);
          }
        }
      }
    }

    void addRules(Iterable<css.TreeNode> rules) {
      for (final rule in rules) {
        if (rule is css.RuleSet) {
          addRuleSet(rule);
        } else if (rule is css.MediaDirective) {
          if (media.matches(rule.mediaQueries)) {
            addRules(rule.rules);
          }
        }
      }
    }

    for (final style in root.querySelectorAll('style')) {
      final mediaList = style.attributes['media']?.trim() ?? '';
      if (mediaList.isNotEmpty) {
        final directive = css
            .parse('@media $mediaList {}')
            .topLevels
            .whereType<css.MediaDirective>()
            .firstOrNull;
        if (directive == null || !media.matches(directive.mediaQueries)) {
          continue;
        }
      }

      addRules(css.parse(style.text).topLevels);
    }

    return styleSheet._matches.isEmpty ? null : styleSheet;
  }
}

/// Evaluates media queries against the [context] of a `HtmlWidget`.
///
/// Evaluated queries are remembered so that [hasChanged] can tell
/// whether the widget tree must be built again.
class CssMedia {
  final BuildContext context;
  final MaterialThemeMode materialThemeMode;

  final _evaluated = <(List<css.MediaQuery>, bool)>[];

  CssMedia(this.context, this.materialThemeMode);

  /// Returns `true` if any evaluated query has a different result now.
  bool get hasChanged => _evaluated.any((e) => _matchesAny(e.$1) != e.$2);

  /// Returns `true` if no query has been evaluated.
  bool get isEmpty => _evaluated.isEmpty;

  /// Returns `true` if any of [queries] matches.
  bool matches(List<css.MediaQuery> queries) {
    final result = _matchesAny(queries);
    _evaluated.add((queries, result));
    return result;
  }

  bool _matchesAny(List<css.MediaQuery> queries) =>
      queries.isEmpty || queries.any(_matchesQuery);

  bool _matchesQuery(css.MediaQuery query) {
    final type = query.hasMediaType ? query.mediaType.toLowerCase() : 'all';
    final result = (type == 'all' || type == 'screen') &&
        query.expressions.every(_matchesExpression);
    return query.hasUnary && query.unary == 'NOT' ? !result : result;
  }

  bool _matchesExpression(css.MediaExpression expression) {
    final feature = expression.mediaFeature.toLowerCase();
    final values = expression.exprs.expressions;
    final value = values.length == 1 ? values.first : null;
    if (values.isNotEmpty && value == null) {
      return false;
    }

    final range = feature.startsWith('min-') || feature.startsWith('max-')
        ? feature.substring(0, 4)
        : '';
    switch (feature.substring(range.length)) {
      case 'width':
      case 'device-width':
        return _matchesLength(
            MediaQuery.maybeSizeOf(context)?.width, range, value);
      case 'height':
      case 'device-height':
        return _matchesLength(
            MediaQuery.maybeSizeOf(context)?.height, range, value);
    }

    if (range.isNotEmpty) {
      return false;
    }

    final keyword = value is css.LiteralTerm ? '${value.value}' : null;
    switch (feature) {
      case 'orientation':
        final size = MediaQuery.maybeSizeOf(context);
        if (size == null) {
          return false;
        }
        final orientation =
            size.height >= size.width ? 'portrait' : 'landscape';
        return keyword == null || keyword == orientation;
      case 'prefers-color-scheme':
        final brightness =
            resolveMaterialThemeMode(context, materialThemeMode).brightness;
        return keyword == null || keyword == brightness.name;
    }

    return false;
  }

  static bool _matchesLength(
    double? actual,
    String range,
    css.Expression? expression,
  ) {
    if (actual == null) {
      return false;
    }
    if (expression == null) {
      return range.isEmpty && actual > 0;
    }

    final expected = _px(expression);
    if (expected == null) {
      return false;
    }

    switch (range) {
      case 'min-':
        return actual >= expected;
      case 'max-':
        return actual <= expected;
    }
    return actual == expected;
  }

  static double? _px(css.Expression expression) {
    if (expression is css.EmTerm || expression is css.RemTerm) {
      final value = (expression as css.LiteralTerm).value as num;
      return value * _mediaFontSize;
    }

    if (expression is css.LengthTerm) {
      final value = expression.value as num;
      switch (expression.unit) {
        case css.TokenKind.UNIT_LENGTH_PX:
          return value.toDouble();
        case css.TokenKind.UNIT_LENGTH_PT:
          return value * 96 / 72;
      }
    } else if (expression is css.NumberTerm && expression.value == 0) {
      return 0;
    }

    return null;
  }
}

@immutable
class _Match {
  final List<css.Declaration> declarations;
  final int order;
  final int specificity;

  const _Match(this.specificity, this.order, this.declarations);

  static int compare(_Match a, _Match b) {
    final cmp = a.specificity.compareTo(b.specificity);
    return cmp == 0 ? a.order.compareTo(b.order) : cmp;
  }
}

List<dom.Element>? _querySelectorAll(
  dom.DocumentFragment root,
  String selector,
) {
  try {
    return root.querySelectorAll(selector);
  } on FormatException {
    return null;
    // the html package does not implement selectors such as `:hover`
    // ignore: avoid_catching_errors
  } on UnimplementedError {
    return null;
  }
}

// https://www.w3.org/TR/selectors-3/#specificity
int _specificity(css.Selector selector) {
  var ids = 0;
  var classes = 0;
  var types = 0;

  void count(css.SimpleSelector simple) {
    if (simple is css.NegationSelector) {
      final arg = simple.negationArg;
      if (arg != null) {
        count(arg);
      }
    } else if (simple is css.IdSelector) {
      ids++;
    } else if (simple is css.ClassSelector ||
        simple is css.AttributeSelector ||
        simple is css.PseudoClassSelector) {
      classes++;
    } else if (simple is css.PseudoElementSelector || !simple.isWildcard) {
      types++;
    }
  }

  for (final sequence in selector.simpleSelectorSequences) {
    count(sequence.simpleSelector);
  }

  return (ids << 20) | (classes << 10) | types;
}
