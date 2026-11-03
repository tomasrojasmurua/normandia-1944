// Servidor del cooperativo de Normandy 1944 (Cloudflare Workers + Durable Objects).
// No simula nada: solo REENVÍA mensajes entre los jugadores de una sala.
// El primer jugador que entra es el anfitrión (su celular corre la IA).
//
//   wss://<este servidor>/sala/<CODIGO>   → entra a la sala (máximo 4 jugadores)
//
// Mensajes del servidor (JSON):
//   {"t":"hola","id":"a1b2","otros":["c3d4"],"anfitrion":true,"puesto":0}   al entrar
//      puesto = 0..3, el primero libre: decide su escuadra y su nombre
//   {"t":"entra","id":"c3d4"} / {"t":"sale","id":"c3d4","anfitrion":false}  a los demás
//   {"t":"anfitrion","id":"c3d4"}   se fue el anfitrión: este jugador toma su lugar
//   {"t":"llena"}                    la sala tiene 4
// Todo lo demás que manda un jugador se reenvía tal cual a los otros, salvo
// {"t":"ping",...}, que vuelve al mismo jugador como {"t":"pong",...} (para medir el retraso).

const MAXIMO = 4;

export class Sala {
  constructor(state, env) {
    this.state = state;
  }

  async fetch(request) {
    const conectados = this.state.getWebSockets().filter((w) => !(w.deserializeAttachment() || {}).salio);
    const pair = new WebSocketPair();
    const [cliente, servidor] = Object.values(pair);
    this.state.acceptWebSocket(servidor);
    if (conectados.length >= MAXIMO) {
      servidor.send(JSON.stringify({ t: "llena" }));
      servidor.close(4000, "sala llena");
      return new Response(null, { status: 101, webSocket: cliente });
    }
    const datos = conectados.map((w) => w.deserializeAttachment() || {});
    const id = crypto.randomUUID().slice(0, 4);
    const esAnfitrion = !datos.some((d) => d.anfitrion);
    let puesto = 0;
    while (datos.some((d) => d.puesto === puesto)) puesto++;
    servidor.serializeAttachment({ id, anfitrion: esAnfitrion, puesto });
    const otros = datos.map((d) => d.id).filter(Boolean);
    servidor.send(JSON.stringify({ t: "hola", id, otros, anfitrion: esAnfitrion, puesto }));
    this.difundir(servidor, { t: "entra", id });
    return new Response(null, { status: 101, webSocket: cliente });
  }

  webSocketMessage(ws, mensaje) {
    if (typeof mensaje === "string" && mensaje.startsWith('{"t":"ping"')) {
      ws.send('{"t":"pong"' + mensaje.slice(11));
      return;
    }
    for (const w of this.state.getWebSockets()) {
      if (w !== ws) {
        try { w.send(mensaje); } catch (e) { /* se fue */ }
      }
    }
  }

  webSocketClose(ws) {
    const datos = ws.deserializeAttachment();
    if (!datos || !datos.id || datos.salio) return;
    ws.serializeAttachment({ ...datos, salio: true, anfitrion: false, puesto: -1 });
    this.difundir(ws, { t: "sale", id: datos.id, anfitrion: !!datos.anfitrion });
    if (datos.anfitrion) {
      // Traspaso: el que lleva más tiempo en la sala pasa a ser el anfitrión
      const quedan = this.state.getWebSockets().filter((w) => w !== ws);
      for (const w of quedan) {
        const d = w.deserializeAttachment();
        if (d && d.id && !d.salio) {
          w.serializeAttachment({ ...d, anfitrion: true });
          this.difundir(ws, { t: "anfitrion", id: d.id });
          break;
        }
      }
    }
  }

  webSocketError(ws) {
    this.webSocketClose(ws);
  }

  difundir(desde, obj) {
    const texto = JSON.stringify(obj);
    for (const w of this.state.getWebSockets()) {
      if (w !== desde) {
        try { w.send(texto); } catch (e) { /* se fue */ }
      }
    }
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/") {
      return new Response("Normandy 1944 - servidor del cooperativo OK");
    }
    const m = url.pathname.match(/^\/sala\/([A-Z0-9]{1,8})$/);
    if (!m) {
      return new Response("No encontrado", { status: 404 });
    }
    if (request.headers.get("Upgrade") !== "websocket") {
      return new Response("Se necesita WebSocket", { status: 426 });
    }
    const sala = env.SALAS.get(env.SALAS.idFromName(m[1]), { locationHint: "sam" });
    return sala.fetch(request);
  },
};
