import 'package:ai_fitness/features/nutrition/planner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('planejamento valida estrutura antes de persistir', () {
    final plan = validateMealPlan(
      '{"recipes":[{"name":"Combinação de teste","ingredients":["Ingrediente teste"],"instructions":"Preparo de teste"}],"shopping":[]}',
    );
    expect((plan['recipes'] as List).length, 1);
    for (final response in [
      '{}',
      '{"recipes":[],"shopping":[]}',
      '{"recipes":[{"name":"x","ingredients":"inválido","instructions":"x"}],"shopping":[]}',
    ]) {
      expect(() => validateMealPlan(response), throwsFormatException);
    }
  });
}
