import 'package:flutter_ebook_app/src/common/data/local/local_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('initialization makes preferences available before providers read them', () async {
    SharedPreferences.setMockInitialValues({'theme': 'light'});

    await LocalStorage.initialize();

    expect(LocalStorage().getSharedPreferences(), isNotNull);
    expect(LocalStorage().getSharedPreferences()!.getString('theme'), 'light');
  });
}
