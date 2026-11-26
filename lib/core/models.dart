import 'dart:convert';

typedef Json = Map<String, dynamic>;

double number(dynamic value, {double min = 0, double max = 100000}) {
  final n = value is num
      ? value.toDouble()
      : double.tryParse('$value'.replaceAll(',', '.'));
  if (n == null || !n.isFinite || n < min || n > max) {
    throw FormatException('Informe um número entre $min e $max.');
  }
  return n;
}

String text(dynamic value, {int max = 500, bool optional = false}) {
  if (value is! String ||
      value.trim().length > max ||
      (!optional && value.trim().isEmpty)) {
    throw const FormatException('Texto ausente ou muito longo.');
  }
  return value.trim();
}

String dayKey(DateTime day) =>
    '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
String dateLabel(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

Json parseObject(String response) {
  var source = response.trim();
  if (source.startsWith('```') && source.endsWith('```')) {
    source = source
        .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
        .replaceFirst(RegExp(r'\s*```$'), '');
  }
  if (source.length > 100000) {
    throw const FormatException('Resposta muito grande.');
  }
  final decoded = jsonDecode(source);
  if (decoded is! Json) {
    throw const FormatException('A IA não retornou um objeto JSON.');
  }
  return decoded;
}

class Macros {
  final double kcal, protein, carbs, fat, fiber;
  const Macros(this.kcal, this.protein, this.carbs, this.fat, [this.fiber = 0]);
  static const zero = Macros(0, 0, 0, 0);
  factory Macros.fromJson(Json json) => Macros(
    number(json['kcal']),
    number(json['protein']),
    number(json['carbs']),
    number(json['fat']),
    number(json['fiber'] ?? 0),
  );
  Json toJson() => {
    'kcal': kcal,
    'protein': protein,
    'carbs': carbs,
    'fat': fat,
    'fiber': fiber,
  };
  Macros operator +(Macros other) => Macros(
    kcal + other.kcal,
    protein + other.protein,
    carbs + other.carbs,
    fat + other.fat,
    fiber + other.fiber,
  );
  Macros scale(double value) => Macros(
    kcal * value,
    protein * value,
    carbs * value,
    fat * value,
    fiber * value,
  );
}

class Ingredient {
  final String name, source;
  final bool estimated;
  final String? uncertainty;
  final double grams;
  final Macros per100;
  const Ingredient({
    required this.name,
    required this.grams,
    required this.per100,
    required this.source,
    this.estimated = false,
    this.uncertainty,
  });
  factory Ingredient.fromJson(Json json) => Ingredient(
    name: text(json['name'], max: 120),
    grams: number(json['grams'], min: 0.1, max: 10000),
    per100: Macros.fromJson(json['per100'] as Json),
    source: text(json['source']),
    estimated: json['estimated'] == true,
    uncertainty: json['uncertainty'] == null ? null : text(json['uncertainty']),
  );
  Macros get total => per100.scale(grams / 100);
  Json toJson() => {
    'name': name,
    'grams': grams,
    'per100': per100.toJson(),
    'source': source,
    if (estimated) 'estimated': true,
    if (uncertainty != null) 'uncertainty': uncertainty,
  };
}

class Meal {
  final String name, category;
  final DateTime date;
  final List<Ingredient> ingredients;
  const Meal({
    required this.name,
    required this.category,
    required this.date,
    required this.ingredients,
  });
  factory Meal.fromJson(Json json) => Meal(
    name: text(json['name']),
    category: text(json['category']),
    date: DateTime.parse(json['date'] as String),
    ingredients: (json['ingredients'] as List)
        .map((e) => Ingredient.fromJson(e as Json))
        .toList(),
  );
  Macros get total =>
      ingredients.fold(Macros.zero, (sum, food) => sum + food.total);
  Json toJson() => {
    'name': name,
    'category': category,
    'date': date.toIso8601String(),
    'ingredients': ingredients.map((e) => e.toJson()).toList(),
  };
}

const goals = [
  'Emagrecer',
  'Ganhar massa muscular',
  'Manter peso',
  'Melhorar condicionamento',
  'Recomposição corporal',
  'Melhorar hábitos alimentares',
];

class NutritionTargets {
  final double expenditure;
  final Macros macros;
  const NutritionTargets(this.expenditure, this.macros);
}

NutritionTargets? calculateTargets(Json profile) {
  final age = number(profile['age'], min: 1, max: 120);
  if (age < 18 || profile['clinical'] == true || profile['pregnant'] == true) {
    return null;
  }
  final weight = number(profile['weight'], min: 25, max: 350);
  final height = number(profile['height'], min: 100, max: 250);
  final sex = profile['formulaSex'];
  // ponytail: Mifflin-St Jeor requires its sex coefficient; absent coefficient means no automatic target.
  if (sex != 'male' && sex != 'female') return null;
  final activity = number(profile['activity'], min: 1.2, max: 1.9);
  final basal =
      10 * weight + 6.25 * height - 5 * age + (sex == 'male' ? 5 : -161);
  final expenditure = basal * activity;
  final goal = profile['goal'];
  final factor = goal == 'Emagrecer'
      ? .9
      : goal == 'Ganhar massa muscular'
      ? 1.05
      : 1.0;
  final kcal = (expenditure * factor).clamp(
    sex == 'male' ? 1500.0 : 1200.0,
    6500.0,
  );
  final protein =
      weight *
      (goal == 'Ganhar massa muscular' || goal == 'Recomposição corporal'
          ? 1.6
          : 1.4);
  final fat = kcal * .3 / 9;
  return NutritionTargets(
    expenditure,
    Macros(
      kcal,
      protein,
      (kcal - protein * 4 - fat * 9).clamp(0, kcal) / 4,
      fat,
    ),
  );
}

List<Json> validateFoodAnalysis(String response) {
  final foods = parseObject(response)['foods'];
  if (foods is List && foods.isEmpty) {
    throw const FormatException(
      'Não foi possível identificar alimentos. Descreva quantidade, tamanho e preparo ou use outra foto.',
    );
  }
  if (foods is! List || foods.isEmpty || foods.length > 25) {
    throw const FormatException('Lista de alimentos inválida.');
  }
  return foods.map((item) {
    if (item is! Json) throw const FormatException('Alimento inválido.');
    final values = item['per100'];
    if (values is! Json) {
      throw const FormatException(
        'Estimativa nutricional ausente. Tente novamente ou informe os valores manualmente.',
      );
    }
    final macros = Macros(
      number(values['kcal'], max: 950),
      number(values['protein'], max: 100),
      number(values['carbs'], max: 100),
      number(values['fat'], max: 100),
      number(values['fiber'], max: 100),
    );
    if (macros.protein + macros.carbs + macros.fat > 105 ||
        macros.fiber > macros.carbs ||
        (macros.kcal == 0 && macros.protein + macros.carbs + macros.fat > 0)) {
      throw const FormatException(
        'Estimativa nutricional inconsistente. Tente novamente ou revise manualmente.',
      );
    }
    return <String, dynamic>{
      'name': text(item['name'], max: 120),
      'grams': number(item['grams'], min: 1, max: 5000),
      'uncertainty': text(item['uncertainty']),
      'per100': macros.toJson(),
      'estimated': true,
      'source': 'Estimativa da IA — não verificada em tabela ou rótulo',
    };
  }).toList();
}

const workoutDays = [
  'Segunda',
  'Terça',
  'Quarta',
  'Quinta',
  'Sexta',
  'Sábado',
  'Domingo',
];
const workoutFocuses = [
  'Corpo inteiro',
  'Braços',
  'Peito',
  'Costas',
  'Ombros',
  'Pernas',
  'Glúteos',
  'Abdômen',
  'Cardio',
  'Mobilidade',
];

final _youtubeId = RegExp(r'^[A-Za-z0-9_-]{11}$');
final _catalogId = RegExp(
  r'^(clip-[a-z][0-9]{2}|flow-[0-9]{4}|commons-[0-9]{2}|wger-[0-9]{2})$',
);

String? exerciseCatalogId(Object? value) =>
    value is String && _catalogId.hasMatch(value) ? value : null;

String? youtubeVideoId(Object? value) {
  if (value is! String) return null;
  final input = value.trim();
  if (_youtubeId.hasMatch(input)) return input;
  final url = Uri.tryParse(input);
  if (url == null ||
      url.scheme != 'https' ||
      url.hasPort ||
      url.userInfo.isNotEmpty) {
    return null;
  }
  final segments = url.pathSegments;
  final String? id;
  if (url.host == 'youtu.be' && segments.length == 1) {
    id = segments.single;
  } else if (const [
    'youtube.com',
    'www.youtube.com',
    'm.youtube.com',
  ].contains(url.host)) {
    id = url.path == '/watch'
        ? url.queryParameters['v']
        : segments.length == 2 &&
              const ['shorts', 'embed'].contains(segments.first)
        ? segments.last
        : null;
  } else {
    return null;
  }
  return id != null && _youtubeId.hasMatch(id) ? id : null;
}

Json validateWorkout(Json json, {bool generated = false}) {
  final exercises = json['exercises'];
  if (exercises is! List || exercises.isEmpty || exercises.length > 20) {
    throw const FormatException('Treino precisa de 1 a 20 exercícios.');
  }
  final names = <String>{};
  final days = json['days'] ?? <int>[];
  if (days is! List ||
      days.any((d) => d is! int || d < 1 || d > 7) ||
      days.toSet().length != days.length) {
    throw const FormatException(
      'Dias do treino inválidos. Selecione dias de segunda a domingo.',
    );
  }
  final focus = json['focus'] ?? <String>[];
  if (focus is! List ||
      focus.any((f) => !workoutFocuses.contains(f)) ||
      focus.toSet().length != focus.length) {
    throw const FormatException(
      'Foco muscular inválido. Escolha grupos disponíveis.',
    );
  }
  for (final exercise in exercises) {
    if (exercise is! Json ||
        !names.add(text(exercise['name'], max: 120).toLowerCase())) {
      throw const FormatException(
        'Use nomes únicos para exercícios da mesma rotina.',
      );
    }
  }
  return {
    'name': text(json['name'], max: 120),
    'days': (days.cast<int>().toList()..sort()),
    'focus': focus.cast<String>(),
    'preferences': text(json['preferences'] ?? '', max: 1000, optional: true),
    'exercises': exercises.map((e) {
      if (e is! Json) throw const FormatException('Exercício inválido.');
      final exerciseName = text(e['name'], max: 120);
      double value(
        String key,
        String label,
        double min,
        double max, {
        bool integer = false,
      }) {
        try {
          final n = number(e[key], min: min, max: max);
          if (integer && n != n.round()) throw const FormatException();
          return n;
        } on FormatException {
          throw FormatException(
            '$exerciseName: $label deve ser ${integer ? 'um número inteiro' : 'um número'} entre ${min.toInt()} e ${max.toInt()}.',
          );
        }
      }

      final sets = value('sets', 'séries', 1, 8, integer: true);
      final video = generated
          ? null
          : text(e['videoId'] ?? '', max: 500, optional: true);
      final videoId = youtubeVideoId(video);
      if (video != null && video.isNotEmpty && videoId == null) {
        throw FormatException(
          '$exerciseName: informe um link válido do YouTube.',
        );
      }
      return <String, dynamic>{
        'name': text(e['name'], max: 120),
        'muscle': text(e['muscle'], max: 120),
        'sets': sets.toInt(),
        'reps': value('reps', 'repetições', 1, 100, integer: true).toInt(),
        // ponytail: absent/zero AI rest uses conservative 60 s; timed-set schema needs separate duration field.
        'rest':
            generated &&
                (e['rest'] == null || double.tryParse('${e['rest']}') == 0)
            ? 60
            : value(
                'rest',
                'descanso em segundos',
                10,
                600,
                integer: true,
              ).toInt(),
        'load': generated
            ? 0.0
            : e['load'] == null
            ? 0.0
            : value('load', 'carga em kg', 0, 1000),
        'instructions': text(e['instructions']),
        'safety': text(e['safety']),
        'alternatives': text(e['alternatives']),
        'videoId': ?videoId,
        'catalogId': ?(generated ? null : exerciseCatalogId(e['catalogId'])),
      };
    }).toList(),
  };
}
