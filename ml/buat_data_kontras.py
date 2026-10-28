"""Membuat data kontras agar model tidak menyamakan "ada nomor" = penipuan.

Masalah di dataset SMS: 52% pesan penipuan memuat nomor HP/rekening,
sedangkan pesan normal hanya 1%. Akibatnya model lama menilai pesan biasa
berisi nomor sebagai penipuan, dan penipuan TANPA nomor lolos.

Script ini menulis data/kontras.csv berisi:
  - pesan NORMAL yang memuat nomor HP / rekening / e-wallet (label 0)
  - pesan PROMO yang memuat nomor kontak (label 2)
  - pesan PENIPUAN tanpa nomor sama sekali (label 1)

Nomor, nama, bank, dan nominal diacak dalam berbagai format. Semua data
ini SINTETIS (template tulisan tangan), bukan pesan asli.

Pemakaian:  python buat_data_kontras.py
"""

import csv
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "data" / "kontras.csv"
SEED = 7
COPIES = 3  # tiap template normal/promo diisi 3x dengan nilai acak berbeda

rng = random.Random(SEED)

NAMA = ["Andi", "Budi", "Citra", "Dewi", "Eko", "Fajar", "Gita", "Hana", "Irfan",
        "Joko", "Kiki", "Lina", "Made", "Nanda", "Oki", "Putri", "Rizki", "Sari",
        "Tono", "Umi", "Vina", "Wahyu", "Yusuf", "Zahra", "Bu Ani", "Pak Darto",
        "Mbak Ratna", "Mas Arif", "Bang Togar", "Teh Euis", "Kak Nisa", "Om Hendra"]
BANK = ["BCA", "BRI", "BNI", "Mandiri", "BSI", "CIMB Niaga", "Permata", "BTN",
        "Bank Jago", "SeaBank", "Danamon", "BPD Jateng"]
EWALLET = ["Dana", "OVO", "GoPay", "ShopeePay", "LinkAja"]
PREFIX = ["0811", "0812", "0813", "0821", "0822", "0823", "0852", "0853", "0857",
          "0858", "0877", "0878", "0881", "0895", "0896", "0897", "0838", "0831"]


def hp() -> str:
    p, rest = rng.choice(PREFIX), "".join(rng.choice("0123456789") for _ in range(rng.randint(7, 8)))
    full = p + rest
    style = rng.randint(0, 4)
    if style == 0:
        return full
    if style == 1:
        return f"{full[:4]}-{full[4:8]}-{full[8:]}"
    if style == 2:
        return f"{full[:4]} {full[4:8]} {full[8:]}"
    if style == 3:
        return f"+62 {full[1:4]} {full[4:8]} {full[8:]}"
    return "62" + full[1:]


def rek() -> str:
    n = "".join(rng.choice("0123456789") for _ in range(rng.randint(10, 13)))
    style = rng.randint(0, 2)
    if style == 0:
        return n
    if style == 1:
        return " ".join(n[i:i + 4] for i in range(0, len(n), 4))
    return f"{n[:3]}-{n[3:6]}-{n[6:]}"


def telp_kantor() -> str:
    kode = rng.choice(["021", "022", "024", "0274", "031", "0361", "061", "0411"])
    return f"{kode}-{rng.randint(100000, 9999999)}" if rng.random() < 0.5 else f"({kode}) {rng.randint(100000, 9999999)}"


def nominal() -> str:
    v = rng.choice([25, 30, 50, 75, 100, 120, 150, 200, 250, 350, 500, 750])
    return rng.choice([f"{v}rb", f"Rp{v}.000", f"{v} ribu", f"Rp {v}.000"])


def isi(t: str) -> str:
    return t.format(nama=rng.choice(NAMA), nama2=rng.choice(NAMA), hp=hp(), rek=rek(),
                    bank=rng.choice(BANK), ewallet=rng.choice(EWALLET),
                    telp=telp_kantor(), nominal=nominal(),
                    angka=rng.randint(10000000, 99999999))


NORMAL_DENGAN_NOMOR = [
    "Halo semua, ini nomor baruku {hp}. Nomor lama sudah nggak aktif ya.",
    "{nama}, simpan nomorku yang baru {hp}, yang lama dipakai buat kerja.",
    "Kalau ada perlu soal acara besok, kontak aku di {hp} aja.",
    "Ini nomor {nama}, dia yang ngurus konsumsi: {hp}.",
    "Nomor WA bidan desa {hp}, kalau mau periksa kehamilan bisa janjian dulu.",
    "Tolong catat nomor sopir travelnya {hp}, nanti dia jemput jam 5 pagi.",
    "Tukang servis kulkas yang kemarin namanya {nama}, nomornya {hp}, harganya bersahabat.",
    "Grup alumni pindah ke nomor admin baru {hp}, tolong save biar nggak ketinggalan info.",
    "Nomor wali kelas anakku {hp}, kalau kamu mau tanya soal kegiatan sekolah.",
    "Pak RT minta warga yang mau lapor kehilangan langsung hubungi {hp}.",
    "Nanti kalau sudah sampai stasiun telepon aku di {hp}, aku tunggu di pintu keluar.",
    "Ini kontak penjahit langganan Mama, {nama}, {hp}. Jahitannya rapi.",
    "Kalau aku nggak bisa dihubungi, telepon suamiku di {hp}.",
    "Nomor kantor cabang kami {telp}, buka Senin sampai Jumat jam 8 sampai 4 sore.",
    "Untuk reservasi meja makan malam keluarga, aku sudah telepon restorannya di {telp}.",
    "Puskesmas kecamatan bisa dihubungi di {telp} kalau mau tanya jadwal imunisasi.",
    "Arisan bulan ini {nominal}, transfer ke {bank} {rek} a.n. {nama} ya ibu-ibu.",
    "Uang kas kelas {nominal} per anak, kirim ke rekening {bank} {rek} atas nama {nama}.",
    "Patungan bensin {nominal} per orang ke {ewallet} {hp} ({nama}), makasih teman-teman.",
    "Bayar kos bulan ini ke {bank} {rek} seperti biasa ya Mbak, terima kasih.",
    "Ini nomor rekening aku buat ganti uang tiket kemarin: {bank} {rek} a.n. {nama}.",
    "Kak, pembayaran pesanan kue bisa ke {bank} {rek} a.n. {nama}, nanti kirim bukti transfernya ya.",
    "Iuran sampah dan keamanan {nominal}, bisa tunai ke Pak RT atau transfer ke {bank} {rek}.",
    "Gaji lembur minggu lalu sudah masuk ke rekening {rek}, tolong dicek ya.",
    "Pak, untuk reimburse biaya perjalanan dinas saya, rekening saya {bank} {rek}.",
    "Sumbangan untuk tetangga yang kena musibah bisa lewat {bank} {rek} a.n. Panitia Peduli RW 03.",
    "Uang sewa lapangan sudah aku bayar, sisanya {nominal} transfer ke {ewallet} {hp} ya.",
    "Mas, aku sudah transfer DP {nominal} ke rekening {bank} {rek}, tolong dicek.",
    "Ini nomor rekening kampus untuk bayar UKT: {bank} {rek}, jangan salah ketik ya dek.",
    "Infaq pembangunan masjid bisa disalurkan ke {bank} {rek} a.n. DKM Al Ikhlas.",
    "Bu, uang belanja minggu ini sudah aku kirim ke {ewallet} {hp}.",
    "Tagihan listrik sudah aku bayar, ID pelanggannya {angka} kalau mau dicek.",
    "Nomor resi kirimanmu {angka}, bisa dilacak di aplikasi ekspedisinya.",
    "Nomor antrean kita di kantor imigrasi B{angka}, masih lama, aku ke kantin dulu.",
    "Nomor pesanan tiket kereta kita {angka}, kursi di gerbong 3.",
    "Ini nomor pendaftaran lomba anakmu {angka}, simpan buat ambil nomor dada.",
    "Nomor polis asuransi kesehatan Bapak {angka}, kartu fisiknya ada di laci lemari.",
    "Nomor induk siswa {nama} {angka}, diminta untuk pendaftaran beasiswa.",
    "Ya ampun, aku baru sadar salah transfer ke rekening {rek}, untung itu rekening kakakku sendiri.",
    "Sudah aku tulis di grup, untuk konfirmasi kehadiran hubungi panitia di {hp} atau {hp}.",
    "{nama}, nomor HP dokter anak yang bagus itu {hp}, praktiknya sore.",
    "Kalau mau pesan nasi kotak buat pengajian, aku punya kenalan katering, ini nomornya {hp}.",
    "Teman-teman, ini rekening untuk kado pernikahan {nama}: {bank} {rek} a.n. {nama2}. Seikhlasnya ya.",
    "Mas kurir, saya di rumah kok, kalau bingung alamatnya telepon saja {hp}.",
    "Pak, saya sopir ojek yang tadi, nomor saya {hp} kalau mau pesan lagi besok pagi.",
    "Nomor darurat pemadam kebakaran di sini {telp}, aku tempel di kulkas.",
    "Aku sudah dapat nomor tukang ledeng {hp}, besok pagi dia datang benerin pipa bocor.",
    "Nomor rekening untuk bayar SPP bulan ini masih sama, {bank} {rek}, kata bagian TU.",
    "Ini nomor HP Mbah di kampung {hp}, sesekali telepon beliau ya, kangen katanya.",
    "Pengumuman: pendaftaran ulang mahasiswa baru bisa tanya ke bagian akademik {telp}.",
    "Sebelum transfer, pastikan nomor rekeningnya benar ya: {bank} {rek} a.n. {nama}. Aku nggak mau salah kirim lagi.",
    "Hasil lab Bapak sudah keluar, nomor registrasinya {angka}, bisa diambil di loket 2.",
    "Kemarin aku ketemu {nama} di pasar, dia titip nomor barunya {hp}.",
    "Jadwal les privat dipindah ke Kamis, kalau ada perubahan guru lesnya bisa dihubungi di {hp}.",
    "Uang hasil jual motor sudah masuk ke rekening {bank} {rek}, makasih banyak Bang.",
    "Nomor kontak HRD untuk tanya slip gaji {telp} ext 214, jam kerja saja ya.",
    "Nomor meja kita 12, nomor reservasinya {angka}, atas nama {nama}.",
    "Tolong kirim nomor rekeningmu, aku mau ganti uang bensin kemarin.",
    "Nomor ponsel tetangga sebelah {hp}, kalau aku lagi dinas dan ada apa-apa di rumah.",
    "Rekening tabungan anak sudah dibuka di {bank}, nomornya {rek}, buku tabungannya aku simpan.",
]

PROMO_DENGAN_NOMOR = [
    "Promo akhir bulan! Diskon 25% semua produk skincare, order via WA {hp}.",
    "Katering harian mulai {nominal} per porsi, menu ganti tiap hari. Pesan di {hp}.",
    "Jasa cuci sofa dan kasur panggilan, harga mulai {nominal}. Hubungi {hp}.",
    "Toko bangunan kami buka cabang baru! Gratis ongkir area kota, telepon {telp}.",
    "Promo servis AC cuci + cek freon cuma {nominal}, booking di {hp}.",
    "Kursus bahasa Inggris diskon 20% untuk pendaftar minggu ini, info {telp}.",
    "Sewa mobil plus sopir untuk mudik, harga spesial. Hubungi admin {hp}.",
    "Bimbel persiapan UTBK, kelas mulai bulan depan. Daftar via WA {hp}.",
    "Paket aqiqah lengkap mulai 2 juta, bisa cicil. Info {hp}.",
    "Grand opening kedai kopi kami, beli 1 gratis 1 sampai Minggu! Pesan antar {hp}.",
    "Promo pulsa dan paket data murah, transaksi 24 jam via WA {hp}.",
    "Les renang anak, gratis 1 sesi percobaan. Daftar di {hp}.",
    "Jual madu asli langsung dari peternak, {nominal} per botol. Order {hp}.",
    "Jasa desain undangan digital mulai {nominal}, contoh desain bisa minta di {hp}.",
    "Promo internet rumah 50 Mbps, gratis pemasangan bulan ini. Hubungi sales {hp}.",
]

PENIPUAN_TANPA_NOMOR = [
    "Halo, saya dari tim verifikasi WhatsApp. Akun Anda akan dinonaktifkan, mohon kirimkan kode enam digit yang baru masuk.",
    "Bu, saya perawat di IGD. Suami Ibu mengalami kecelakaan dan harus segera ditangani, mohon kirim biaya tindakan sekarang lewat saya.",
    "Kak, aku lagi di luar kota dan dompetku kecopetan. Bisa pinjamkan uang dulu buat tiket pulang? Besok langsung aku ganti.",
    "Akun bank Anda terdeteksi login mencurigakan. Masukkan username dan PIN di halaman pemulihan yang kami kirim agar akun tidak dibekukan.",
    "Selamat! Anda memenangkan undian berhadiah dari toko online. Untuk klaim, cukup bayar pajak hadiah lewat petugas kami.",
    "Kami dari bagian kepegawaian. Anda diterima kerja, silakan transfer biaya seragam dan pelatihan sebelum hari Senin.",
    "Tolong bukakan file ini ya, isinya foto paket yang mau dikirim ke rumahmu: Foto_Paket.apk",
    "Bapak/Ibu, ini surat panggilan sidang tilang elektronik, mohon dipelajari: Surat_Panggilan.apk",
    "Halo, ini undangan khitanan anak kami, detail acaranya ada di file: Undangan_Khitanan.apk",
    "Tagihan BPJS Anda menunggak dan kartu akan diblokir. Unduh aplikasi pembaruan data berikut dan izinkan semua akses.",
    "Cashback jutaan menunggu! Login ke akun e-wallet kamu lewat link promo kami dan masukkan PIN untuk mencairkan.",
    "Maaf mengganggu, tadi aku salah kirim kode verifikasi ke HP kamu. Tolong kirim balik kodenya ya, penting banget.",
    "Ini aku, adikmu. HP-ku rusak jadi pinjam punya teman. Aku butuh uang mendesak buat bayar kuliah hari ini, jangan bilang Ayah dulu.",
    "Pak, saya sekretaris direktur. Beliau minta dibelikan voucher belanja untuk klien sekarang juga, kodenya kirim ke saya, nanti diganti.",
    "Paket Anda tertahan di bea cukai dan akan disita jika denda tidak dibayar hari ini. Hubungi petugas kami untuk pembayaran.",
    "Investasi emas digital dijamin untung berlipat dalam seminggu, tanpa risiko. Daftar sekarang, slot tinggal sedikit!",
    "Kerja paruh waktu dari HP, cukup like video dapat komisi. Untuk naik level, isi saldo tugas dulu ya kak.",
    "Akun media sosial kamu dilaporkan melanggar aturan. Ajukan banding di halaman kami dengan login ulang dalam 24 jam.",
    "Kamu terpilih dapat bantuan sosial tunai. Kirim foto KTP, KK, dan selfie ke admin supaya dana bisa dicairkan.",
    "Hai, kamu dapat hadiah HP baru dari program ulang tahun toko. Ongkos kirim dan asuransinya ditanggung penerima ya.",
    "Kami dari customer service marketplace. Pesanan kamu bermasalah, refund bisa diproses kalau kamu sebutkan kode OTP yang masuk.",
    "Nak, Ayah ditangkap polisi karena salah paham. Butuh uang jaminan sekarang, jangan telepon siapa-siapa dulu.",
    "Tolong buka foto ini, kayaknya kamu ada di foto ini deh: Lihat_Foto.apk",
    "Poin kartu kredit Anda akan hangus. Tukarkan sekarang dengan memasukkan nomor kartu dan kode CVV di formulir kami.",
    "Selamat siang, saya petugas pajak. Anda punya tunggakan pajak dan akan dikenai sanksi jika tidak segera menyelesaikan pembayaran lewat saya.",
    "Pinjaman online langsung cair tanpa BI checking. Syaratnya cuma bayar biaya administrasi di depan.",
    "Dear customer, your account is suspended. Verify your identity on our page to restore access.",
    "Aku dari tim undian aplikasi belanja. Kamu menang mobil, tapi harus transfer biaya balik nama dulu sebelum mobil dikirim.",
    "Mbak, saya kurir. Barang COD-nya sudah saya titip di pos satpam, ongkosnya ditransfer saja ke saya sekarang ya.",
    "Sistem kami mendeteksi kartu ATM Anda digandakan. Untuk keamanan, sebutkan PIN lama agar kartu bisa diganti.",
    "Hai kak, kamu lolos jadi brand ambassador. Untuk kontrak, bayar biaya pembuatan ID card dan pelatihan dulu ya.",
    "Ini dari admin grup arisan online, putaran kamu bisa dipercepat kalau setor dana tambahan hari ini.",
    "Saya ustaz pengasuh pondok, kami sedang butuh bantuan mendesak. Transfer infaq sekarang, insyaallah rezeki dilipatgandakan berkali-kali.",
    "Kak, akun game kamu menang event. Login lewat link kami pakai email dan password untuk ambil hadiah diamond.",
    "Data kependudukan Anda bermasalah. Segera perbarui dengan mengirim foto KTP dan nama ibu kandung ke petugas kami.",
]


def main() -> None:
    rows = []
    for t in NORMAL_DENGAN_NOMOR:
        for _ in range(COPIES):
            rows.append((isi(t), 0))
    for t in PROMO_DENGAN_NOMOR:
        for _ in range(COPIES):
            rows.append((isi(t), 2))
    for t in PENIPUAN_TANPA_NOMOR:
        rows.append((t, 1))

    seen, unique = set(), []
    for text, label in rows:
        if text not in seen:
            seen.add(text)
            unique.append((text, label))

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["Teks", "label"])
        w.writerows(unique)
    counts = {l: sum(1 for _, x in unique if x == l) for l in (0, 1, 2)}
    print(f"{OUT.name}: {len(unique)} baris (normal {counts[0]}, penipuan {counts[1]}, promo {counts[2]})")


if __name__ == "__main__":
    main()
