/// The kind of trip a tour is, shown as the category chips on the home screen.
enum TourCategory {
  beach('Beach'),
  culture('Culture'),
  adventure('Adventure'),
  city('City'),
  nature('Nature');

  const TourCategory(this.label);

  final String label;
}
