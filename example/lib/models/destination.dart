/// Countries the catalog offers tours in.
enum Destination {
  turkey(
    label: 'Turkey',
    flag: '🇹🇷',
    tagline: 'Where East meets West',
    aliases: ['türkiye', 'turkiye'],
  ),
  uae(
    label: 'UAE',
    flag: '🇦🇪',
    tagline: 'Skylines and golden dunes',
    aliases: ['united arab emirates', 'emirates'],
  ),
  thailand(
    label: 'Thailand',
    flag: '🇹🇭',
    tagline: 'Temples, islands and street food',
    aliases: ['thai'],
  ),
  maldives(
    label: 'Maldives',
    flag: '🇲🇻',
    tagline: 'Lagoons and overwater villas',
  ),
  georgia(
    label: 'Georgia',
    flag: '🇬🇪',
    tagline: 'Caucasus peaks and ancient wine',
    aliases: ['sakartvelo'],
  ),
  uzbekistan(
    label: 'Uzbekistan',
    flag: '🇺🇿',
    tagline: 'Jewels of the Silk Road',
    aliases: ['uzbek'],
  );

  const Destination({
    required this.label,
    required this.flag,
    required this.tagline,
    this.aliases = const [],
  });

  final String label;
  final String flag;
  final String tagline;

  /// Other names people search for, matched by the tour search.
  final List<String> aliases;
}
