import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/features/diary/domain/daily_targets.dart';

void main() {
  test('a role wears its mark: floors ≥, caps ≤, about stays bare', () {
    // The single spelling both screens print — no widget re-derives it.
    expect(TargetRole.about.mark, '');
    expect(TargetRole.atLeast.mark, '≥');
    expect(TargetRole.under.mark, '≤');
  });
}
