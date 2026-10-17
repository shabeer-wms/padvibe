import 'package:flutter_test/flutter_test.dart';
import 'package:padvibe/app/core/layout/breakpoints.dart';

void main() {
  test('window size classes follow Material 3 breakpoints', () {
    expect(WindowSize.ofWidth(599), WindowSize.compact);
    expect(WindowSize.ofWidth(600), WindowSize.medium);
    expect(WindowSize.ofWidth(839), WindowSize.medium);
    expect(WindowSize.ofWidth(840), WindowSize.expanded);
  });

  test(
    'grid columns shrink with the window but never exceed the preference',
    () {
      expect(responsiveGridColumns(width: 1200, preferred: 5), 5);
      expect(responsiveGridColumns(width: 700, preferred: 8), 3);
      expect(responsiveGridColumns(width: 300, preferred: 10), 2);
      expect(responsiveGridColumns(width: 2000, preferred: 4), 4);
    },
  );
}
