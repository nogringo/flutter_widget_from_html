import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '_.dart';

const _red = '[RichText:(#FFFF0000:Foo)]';
const _green = '[RichText:(#FF00FF00:Foo)]';
const _plain = '[RichText:(:Foo)]';
const _anchorRed = '[RichText:(:[SizedBox#a:0.0x10.0](#FFFF0000:Foo))]';

void main() {
  group('selectors', () {
    testWidgets('renders class selector', (WidgetTester tester) async {
      const html = '<style>.x { color: #f00 }</style>'
          '<span class="x">Foo</span>';
      final explained = await explain(tester, html);
      expect(explained, equals(_red));
    });

    testWidgets('renders combinators', (WidgetTester tester) async {
      const html = '<style>div > p span.x { color: #f00 }</style>'
          '<div><p><span><span class="x">Foo</span></span></p></div>';
      final explained = await explain(tester, html);
      expect(explained, equals('[CssBlock:child=$_red]'));
    });

    testWidgets('renders top level element', (WidgetTester tester) async {
      const html = '<style>p { color: #f00 }</style><p>Foo</p>';
      final explained = await explain(tester, html);
      expect(explained, equals('[CssBlock:child=$_red]'));
    });

    testWidgets('renders display: none', (WidgetTester tester) async {
      const html = '<style>.hide { display: none }</style>'
          'Foo<span class="hide">Bar</span>';
      final explained = await explain(tester, html);
      expect(explained, equals(_plain));
    });

    testWidgets('skips unsupported selector', (WidgetTester tester) async {
      const html = '<style>.x:hover, .x::before { color: #0f0 }'
          '.x { color: #f00 }</style>'
          '<span class="x">Foo</span>';
      final explained = await explain(tester, html);
      expect(explained, equals(_red));
    });

    testWidgets('skips invalid CSS', (WidgetTester tester) async {
      const html = '<style>}}} .x { color: #f00 }</style>'
          '<span class="x">Foo</span>';
      final explained = await explain(tester, html);
      expect(explained, anyOf(equals(_red), equals(_plain)));
    });

    testWidgets('renders STYLE in body', (WidgetTester tester) async {
      const html = '<span class="x">Foo</span>'
          '<div><style>.x { color: #f00 }</style></div>';
      final explained = await explain(tester, html);
      expect(explained, equals(_red));
    });
  });

  group('cascade', () {
    testWidgets('prefers higher specificity', (WidgetTester tester) async {
      const html = '<style>#a { color: #f00 } .x { color: #0f0 }</style>'
          '<span id="a" class="x">Foo</span>';
      final explained = await explain(tester, html);
      expect(explained, equals(_anchorRed));
    });

    testWidgets('prefers later rule', (WidgetTester tester) async {
      const html = '<style>.x { color: #f00 } .y { color: #0f0 }</style>'
          '<span class="y x">Foo</span>';
      final explained = await explain(tester, html);
      expect(explained, equals(_green));
    });

    testWidgets('uses highest specificity of group', (tester) async {
      const html = '<style>.x, span { color: #f00 } .y { color: #0f0 }'
          '</style><span class="x y">Foo</span>';
      final explained = await explain(tester, html);
      expect(explained, equals(_green));
    });

    testWidgets('prefers inline style', (WidgetTester tester) async {
      const html = '<style>.x { color: #f00 }</style>'
          '<span class="x" style="color: #0f0">Foo</span>';
      final explained = await explain(tester, html);
      expect(explained, equals(_green));
    });

    testWidgets('prefers customStylesBuilder', (WidgetTester tester) async {
      const html = '<style>.x { color: #f00 }</style>'
          '<span class="x">Foo</span>';
      final explained = await explain(
        tester,
        null,
        hw: HtmlWidget(
          html,
          customStylesBuilder: (e) =>
              e.classes.contains('x') ? {'color': '#0f0'} : null,
          key: hwKey,
        ),
      );
      expect(explained, equals(_green));
    });

    testWidgets('overrides tag default styles', (WidgetTester tester) async {
      const html = '<style>b { font-weight: 400 }</style><b>Foo</b>';
      final explained = await explain(tester, html);
      expect(explained, equals(_plain));
    });
  });

  group('!important', () {
    testWidgets('beats inline style', (WidgetTester tester) async {
      const html = '<style>.x { color: #f00 !important }</style>'
          '<span class="x" style="color: #0f0">Foo</span>';
      final explained = await explain(tester, html);
      expect(explained, equals(_red));
    });

    testWidgets('beats higher specificity', (WidgetTester tester) async {
      const html = '<style>span { color: #f00 !important }'
          '#a { color: #0f0 }</style><span id="a">Foo</span>';
      final explained = await explain(tester, html);
      expect(explained, equals(_anchorRed));
    });

    testWidgets('loses to inline !important', (WidgetTester tester) async {
      const html = '<style>.x { color: #f00 !important }</style>'
          '<span class="x" style="color: #0f0 !important">Foo</span>';
      final explained = await explain(tester, html);
      expect(explained, equals(_green));
    });

    testWidgets('renders inline style', (WidgetTester tester) async {
      const html = '<span style="color: #f00 !important; color: #0f0">'
          'Foo</span>';
      final explained = await explain(tester, html);
      expect(explained, equals(_red));
    });

    testWidgets('overrides longhand with shorthand', (tester) async {
      const html = '<style>.x { padding: 0 !important }</style>'
          '<div class="x" style="padding-left: 10px">Foo</div>';
      final explained = await explain(tester, html);
      expect(explained, equals('[CssBlock:child=$_plain]'));
    });
  });

  group('@media', () {
    Future<String> explainMedia(
      WidgetTester tester,
      String query, {
      Size size = const Size(400, 800),
    }) {
      tester.setWindowSize(size);
      return explain(
        tester,
        '<style>@media $query { .x { color: #f00 } }</style>'
        '<span class="x">Foo</span>',
      );
    }

    testWidgets('renders max-width', (WidgetTester tester) async {
      expect(await explainMedia(tester, '(max-width: 480px)'), equals(_red));
    });

    testWidgets('skips max-width', (WidgetTester tester) async {
      expect(await explainMedia(tester, '(max-width: 399px)'), equals(_plain));
    });

    testWidgets('renders min-width', (WidgetTester tester) async {
      expect(await explainMedia(tester, '(min-width: 400px)'), equals(_red));
    });

    testWidgets('skips min-width', (WidgetTester tester) async {
      expect(await explainMedia(tester, '(min-width: 600px)'), equals(_plain));
    });

    testWidgets('renders max-height', (WidgetTester tester) async {
      expect(await explainMedia(tester, '(max-height: 800px)'), equals(_red));
    });

    testWidgets('renders max-device-width', (WidgetTester tester) async {
      const query = '(max-device-width: 480px)';
      expect(await explainMedia(tester, query), equals(_red));
    });

    testWidgets('renders em', (WidgetTester tester) async {
      expect(await explainMedia(tester, '(max-width: 25em)'), equals(_red));
    });

    testWidgets('renders only screen and', (WidgetTester tester) async {
      const query = 'only screen and (max-width: 480px)';
      expect(await explainMedia(tester, query), equals(_red));
    });

    testWidgets('renders and', (WidgetTester tester) async {
      const query = '(min-width: 300px) and (max-width: 480px)';
      expect(await explainMedia(tester, query), equals(_red));
    });

    testWidgets('skips and', (WidgetTester tester) async {
      const query = '(min-width: 300px) and (max-width: 350px)';
      expect(await explainMedia(tester, query), equals(_plain));
    });

    testWidgets('renders list', (WidgetTester tester) async {
      const query = 'print, (max-width: 480px)';
      expect(await explainMedia(tester, query), equals(_red));
    });

    testWidgets('skips print', (WidgetTester tester) async {
      expect(await explainMedia(tester, 'print'), equals(_plain));
    });

    testWidgets('renders not print', (WidgetTester tester) async {
      expect(await explainMedia(tester, 'not print'), equals(_red));
    });

    testWidgets('skips unknown feature', (WidgetTester tester) async {
      expect(await explainMedia(tester, '(hover: hover)'), equals(_plain));
    });

    testWidgets('renders portrait', (WidgetTester tester) async {
      const query = '(orientation: portrait)';
      expect(await explainMedia(tester, query), equals(_red));
    });

    testWidgets('skips landscape', (WidgetTester tester) async {
      const query = '(orientation: landscape)';
      expect(await explainMedia(tester, query), equals(_plain));
    });

    testWidgets('renders nested', (WidgetTester tester) async {
      const html = '<style>@media screen { @media (max-width: 480px) { '
          '.x { color: #f00 } } }</style><span class="x">Foo</span>';
      tester.setWindowSize(const Size(400, 800));
      final explained = await explain(tester, html);
      expect(explained, equals(_red));
    });

    testWidgets('renders !important', (WidgetTester tester) async {
      const html = '<style>@media (max-width: 480px) { '
          '.x { color: #f00 !important } }</style>'
          '<span class="x" style="color: #0f0">Foo</span>';
      tester.setWindowSize(const Size(400, 800));
      final explained = await explain(tester, html);
      expect(explained, equals(_red));
    });

    group('prefers-color-scheme', () {
      Future<String> explainScheme(
        WidgetTester tester,
        Brightness brightness,
      ) =>
          explain(
            tester,
            null,
            hw: Theme(
              data: ThemeData(brightness: brightness),
              child: HtmlWidget(
                '<style>@media (prefers-color-scheme: dark) { '
                '.x { color: #f00 } }</style><span class="x">Foo</span>',
                key: hwKey,
              ),
            ),
          );

      testWidgets('renders dark', (WidgetTester tester) async {
        expect(await explainScheme(tester, Brightness.dark), equals(_red));
      });

      testWidgets('skips light', (WidgetTester tester) async {
        expect(await explainScheme(tester, Brightness.light), equals(_plain));
      });
    });

    group('STYLE media attribute', () {
      testWidgets('renders screen', (WidgetTester tester) async {
        const html = '<style media="screen">.x { color: #f00 }</style>'
            '<span class="x">Foo</span>';
        final explained = await explain(tester, html);
        expect(explained, equals(_red));
      });

      testWidgets('skips print', (WidgetTester tester) async {
        const html = '<style media="print">.x { color: #f00 }</style>'
            '<span class="x">Foo</span>';
        final explained = await explain(tester, html);
        expect(explained, equals(_plain));
      });
    });

    group('rebuilds', () {
      const html = '<style>@media (max-width: 480px) { '
          '.x { color: #f00 } }</style><span class="x">Foo</span>';

      testWidgets('on resize', (WidgetTester tester) async {
        tester.setWindowSize(const Size(800, 600));
        expect(await explain(tester, html), equals(_plain));

        tester.setWindowSize(const Size(400, 800));
        await tester.pump();
        expect(await explainWithoutPumping(), equals(_red));

        tester.setWindowSize(const Size(800, 600));
        await tester.pump();
        expect(await explainWithoutPumping(), equals(_plain));
      });

      testWidgets('on resize with buildAsync', (WidgetTester tester) async {
        Future<Color?> pumpColor() async {
          // one round to parse, another one for the FutureBuilder
          for (var i = 0; i < 2; i++) {
            await tester.runAsync(
              () => Future.delayed(const Duration(milliseconds: 100)),
            );
            await tester.pump();
          }
          final richText = tester.widget<RichText>(find.byType(RichText));
          return richText.text.style?.color;
        }

        const red = Color(0xFFFF0000);
        tester.setWindowSize(const Size(800, 600));
        await explain(
          tester,
          null,
          hw: HtmlWidget(html, buildAsync: true, key: hwKey),
        );
        expect(await pumpColor(), isNot(equals(red)));

        tester.setWindowSize(const Size(400, 800));
        await tester.pump();
        expect(await pumpColor(), equals(red));
      });

      testWidgets('skips without query change', (WidgetTester tester) async {
        var built = 0;
        tester.setWindowSize(const Size(800, 600));
        await explain(
          tester,
          null,
          hw: HtmlWidget(
            html,
            customStylesBuilder: (_) {
              built++;
              return null;
            },
            key: hwKey,
          ),
        );
        expect(built, greaterThan(0));
        final initial = built;

        tester.setWindowSize(const Size(700, 600));
        await tester.pump();
        expect(built, equals(initial));

        tester.setWindowSize(const Size(400, 800));
        await tester.pump();
        expect(built, greaterThan(initial));
      });
    });
  });
}
