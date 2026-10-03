# Yang perlu ditambah di server (Cloudflare Worker) dan mod

Aplikasi memakai 3 endpoint. Dua yang terakhir mungkin sudah ada di Worker kamu, sesuaikan nama field-nya.

POST /app/login        body {"code":"ABC123"}
  -> 200 {"token","accountID","username"}   | 4xx {"error":"Kode salah atau kedaluwarsa"}
GET  /leaderboard?region=global|id&mode=basic|demon&limit=100
  -> {"entries":[{"rank","accountID","username","mmr","tier"}]}
GET  /me   (Authorization: Bearer <token>)
  -> {"rank","mmr","tier","wins","losses"}   | 401 kalau token tidak valid

## Alur login (aman, tanpa password GD)
1. Di dalam GD, mod menekan tombol "Link App". Mod sudah punya bukti akun
   (token Argon / challenge pesan GD) yang diverifikasi server kamu.
2. Server membuat kode acak 6 karakter, simpan di KV dengan TTL 5 menit:
   KV.put("link:"+code, JSON {accountID, username}, {expirationTtl: 300}).
   Mod menampilkan kode itu di popup.
3. Pemain menempel kode di aplikasi -> POST /app/login.
   Server hapus kode (sekali pakai), buat token sesi acak, simpan di KV
   (mis. TTL 30 hari), kirim balik.

Jangan pernah minta password GD di aplikasi: itu rawan phishing dan password GD
tidak bisa diganti dengan token terbatas.

## Contoh handler Worker
export async function appLogin(req, env) {
  const { code } = await req.json();
  const key = "link:" + String(code || "").toUpperCase();
  const rec = await env.KV.get(key, "json");
  if (!rec) return Response.json({ error: "Kode salah atau kedaluwarsa" }, { status: 400 });
  await env.KV.delete(key);
  const token = crypto.randomUUID() + crypto.randomUUID();
  await env.KV.put("sess:" + token, JSON.stringify(rec), { expirationTtl: 60*60*24*30 });
  return Response.json({ token, accountID: rec.accountID, username: rec.username });
}
