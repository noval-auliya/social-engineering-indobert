/// Skor perlindungan di Beranda: seberapa lengkap perlindungan yang AKTIF
/// di HP ini (bukan "tingkat keamanan" yang tidak bisa diukur), sehingga
/// angkanya jujur dan pengguna tahu apa yang harus dinyalakan.
class ProtectionFactor {
  final String label;
  final String hint; // apa yang harus dilakukan jika belum aktif
  final bool active;
  final int weight;

  const ProtectionFactor(this.label, this.hint, {required this.active, required this.weight});
}

List<ProtectionFactor> protectionFactors({
  required bool aiReady,
  required bool monitorActive,
  required bool alertsActive,
  required bool historySaved,
}) =>
    [
      ProtectionFactor('Model AI IndoBERT aktif', 'Model gagal dimuat; analisis memakai kata kunci',
          active: aiReady, weight: 35),
      ProtectionFactor('Pantauan WhatsApp aktif', 'Izinkan akses notifikasi di Pengaturan',
          active: monitorActive, weight: 35),
      ProtectionFactor('Peringatan pesan berisiko', 'Nyalakan peringatan di Pengaturan',
          active: alertsActive, weight: 20),
      ProtectionFactor('Riwayat tersimpan di HP', 'Nyalakan "Simpan riwayat di HP"',
          active: historySaved, weight: 10),
    ];

int protectionScore(List<ProtectionFactor> factors) =>
    factors.where((f) => f.active).fold(0, (s, f) => s + f.weight);
