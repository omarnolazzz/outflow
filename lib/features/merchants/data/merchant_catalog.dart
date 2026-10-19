import '../../../core/domain/billing_cycle.dart';
import '../domain/entities/merchant.dart';

/// Catálogo predefinido. Vive en código (no en la base de datos) para que las
/// actualizaciones de la app lo amplíen sin migraciones; los comercios
/// personalizados del usuario se guardan aparte.
///
/// Los precios varían por país, así que no se precargan.
abstract final class MerchantCatalog {
  static Merchant _m(String id, String name, SpendCategory c,
          {BillingCycle cycle = const BillingCycle.monthly(), int? window}) =>
      Merchant(
        id: 'cat.$id',
        name: name,
        category: c,
        // Logo oficial incluido en la app (assets/logos/<id>.png).
        logo: MerchantLogo.asset('assets/logos/$id.png'),
        billing: BillingDefaults(cycle: cycle, cancellationWindowDays: window),
      );

  static final List<Merchant> all = [
    // Streaming
    _m('netflix', 'Netflix', SpendCategory.streaming),
    _m('disney', 'Disney+', SpendCategory.streaming),
    _m('max', 'Max', SpendCategory.streaming),
    _m('prime_video', 'Prime Video', SpendCategory.streaming),
    _m('apple_tv', 'Apple TV+', SpendCategory.streaming),
    _m('youtube_premium', 'YouTube Premium', SpendCategory.streaming),
    _m('crunchyroll', 'Crunchyroll', SpendCategory.streaming),
    _m('paramount', 'Paramount+', SpendCategory.streaming),
    // Música
    _m('spotify', 'Spotify', SpendCategory.music),
    _m('apple_music', 'Apple Music', SpendCategory.music),
    _m('youtube_music', 'YouTube Music', SpendCategory.music),
    _m('deezer', 'Deezer', SpendCategory.music),
    _m('tidal', 'Tidal', SpendCategory.music),
    // Operadores móviles
    _m('telcel', 'Telcel', SpendCategory.mobile),
    _m('movistar', 'Movistar', SpendCategory.mobile),
    _m('claro', 'Claro', SpendCategory.mobile),
    _m('att', 'AT&T', SpendCategory.mobile),
    _m('entel', 'Entel', SpendCategory.mobile),
    _m('tigo', 'Tigo', SpendCategory.mobile),
    _m('personal', 'Personal', SpendCategory.mobile),
    _m('vodafone', 'Vodafone', SpendCategory.mobile),
    _m('orange', 'Orange', SpendCategory.mobile),
    _m('tmobile', 'T-Mobile', SpendCategory.mobile),
    _m('verizon', 'Verizon', SpendCategory.mobile),
    // Software e IA
    _m('chatgpt', 'ChatGPT Plus', SpendCategory.software),
    _m('claude', 'Claude Pro', SpendCategory.software),
    _m('m365', 'Microsoft 365', SpendCategory.software, cycle: const BillingCycle.yearly()),
    _m('adobe', 'Adobe Creative Cloud', SpendCategory.software, window: 14),
    _m('notion', 'Notion', SpendCategory.software),
    _m('canva', 'Canva Pro', SpendCategory.software),
    _m('figma', 'Figma', SpendCategory.software),
    _m('copilot', 'GitHub Copilot', SpendCategory.software),
    // Nube
    _m('icloud', 'iCloud+', SpendCategory.cloud),
    _m('google_one', 'Google One', SpendCategory.cloud),
    _m('dropbox', 'Dropbox', SpendCategory.cloud),
    // Juegos
    _m('gamepass', 'Xbox Game Pass', SpendCategory.gaming),
    _m('ps_plus', 'PlayStation Plus', SpendCategory.gaming),
    _m('nintendo', 'Nintendo Switch Online', SpendCategory.gaming, cycle: const BillingCycle.yearly()),
    // Lectura
    _m('kindle', 'Kindle Unlimited', SpendCategory.news),
    _m('audible', 'Audible', SpendCategory.news),
    _m('nyt', 'The New York Times', SpendCategory.news),
    _m('medium', 'Medium', SpendCategory.news),
    // Salud
    _m('strava', 'Strava', SpendCategory.fitness),
    _m('smartfit', 'Smart Fit', SpendCategory.fitness),
    _m('headspace', 'Headspace', SpendCategory.fitness),
    // Educación
    _m('duolingo', 'Duolingo Super', SpendCategory.education),
    _m('coursera', 'Coursera Plus', SpendCategory.education),
    // Compras
    _m('amazon_prime', 'Amazon Prime', SpendCategory.shopping),
    _m('meli_plus', 'Mercado Libre Meli+', SpendCategory.shopping),
    _m('costco', 'Costco', SpendCategory.shopping, cycle: const BillingCycle.yearly()),
    _m('rappi', 'Rappi Pro', SpendCategory.shopping),
    _m('uber_one', 'Uber One', SpendCategory.shopping),
  ];
}
