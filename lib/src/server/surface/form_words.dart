/// The words a form card shows, in the languages of `strings.dart`. The same
/// table is the `words` of `catalog/zehn.basic.json`; the backend and the
/// console copy it from there.
const Map<String, Map<String, String>> ziFormWords = {
  'required': {'uz': 'Bu maydonni to‘ldiring', 'ru': 'Заполните это поле', 'en': 'Fill this in'},
  'length': {'uz': '{min} tadan {max} tagacha belgi kiriting', 'ru': 'От {min} до {max} символов', 'en': 'Use {min} to {max} characters'},
  'length_min': {'uz': 'Kamida {min} ta belgi kiriting', 'ru': 'Не меньше {min} символов', 'en': 'Use at least {min} characters'},
  'length_max': {'uz': 'Ko‘pi bilan {max} ta belgi kiriting', 'ru': 'Не больше {max} символов', 'en': 'Use at most {max} characters'},
  'range': {'uz': '{min} dan {max} gacha son kiriting', 'ru': 'Введите число от {min} до {max}', 'en': 'Enter a number from {min} to {max}'},
  'range_min': {'uz': '{min} yoki undan katta son kiriting', 'ru': 'Введите {min} или больше', 'en': 'Enter {min} or more'},
  'range_max': {'uz': '{max} yoki undan kichik son kiriting', 'ru': 'Введите {max} или меньше', 'en': 'Enter {max} or less'},
  'items': {'uz': '{min} tadan {max} tagacha tanlang', 'ru': 'Выберите от {min} до {max}', 'en': 'Choose {min} to {max}'},
  'items_min': {'uz': 'Kamida {min} tasini tanlang', 'ru': 'Выберите не меньше {min}', 'en': 'Choose at least {min}'},
  'items_max': {'uz': 'Ko‘pi bilan {max} tasini tanlang', 'ru': 'Выберите не больше {max}', 'en': 'Choose at most {max}'},
  'number': {'uz': 'Son kiriting', 'ru': 'Введите число', 'en': 'Enter a number'},
  'email': {'uz': 'Elektron pochta manzilini kiriting', 'ru': 'Введите адрес почты', 'en': 'Enter an email address'},
  'phone': {'uz': 'Telefon raqamini kiriting', 'ru': 'Введите номер телефона', 'en': 'Enter a phone number'},
  'date': {'uz': 'Boshqa sanani tanlang', 'ru': 'Выберите другую дату', 'en': 'Choose another date'},
  'option': {'uz': 'Variantlardan birini tanlang', 'ru': 'Выберите один из вариантов', 'en': 'Choose one of the options'},
  'sent': {'uz': 'Yuborildi', 'ru': 'Отправлено', 'en': 'Sent'},
  'not_answered': {'uz': 'Javob berilmadi', 'ru': 'Без ответа', 'en': 'Not answered'},
  'not_sent': {'uz': 'Yuborilmadi. Qayta urinib ko‘ring.', 'ru': 'Не отправлено. Попробуйте ещё раз.', 'en': 'Not sent. Try again.'},
  'update_app': {'uz': 'Javob berish uchun ilovani yangilang.', 'ru': 'Обновите приложение, чтобы ответить.', 'en': 'Update the app to answer this.'},
  'choose': {'uz': 'Tanlang', 'ru': 'Выбрать', 'en': 'Choose'},
};

/// The word [key] in [language], or in English when this SDK has no such
/// language; `{min}` and `{max}` are filled from [min] and [max]. An unknown
/// key comes back empty.
String ziFormWord(String key, String language, {num? min, num? max}) {
  final words = ziFormWords[key];
  if (words == null) return '';
  return (words[language] ?? words['en']!).replaceAll('{min}', _plain(min)).replaceAll('{max}', _plain(max));
}

/// A whole number without its `.0`.
String _plain(num? n) => n == null ? '' : (n == n.truncate() ? '${n.truncate()}' : '$n');
