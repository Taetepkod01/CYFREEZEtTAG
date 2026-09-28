import "reflect-metadata";
import { Room, Client } from "colyseus";
import { Schema, type, MapSchema } from "@colyseus/schema";

// ── 3D Item Types ───────────────────────────────────────────────────────────
export type ItemType =
  | "speed"
  | "shield"
  | "heater"
  | "banana"
  | "vortex";

// ── 3D Arena Spawns (60x60 Arena: X & Z from -22 to +22, Y = 0.5) ───────────
const SPAWN_3D_POSITIONS = [
  { x: 0, y: 0.5, z: 0 },
  { x: -14, y: 0.5, z: -14 },
  { x: 14, y: 0.5, z: 14 },
  { x: 14, y: 0.5, z: -14 },
  { x: -14, y: 0.5, z: 14 },
  { x: 0, y: 0.5, z: 16 },
  { x: 0, y: 0.5, z: -16 },
  { x: 16, y: 0.5, z: 0 },
  { x: -16, y: 0.5, z: 0 }
];

function randomSpawn3D(): { x: number; y: number; z: number } {
  const sp = SPAWN_3D_POSITIONS[Math.floor(Math.random() * SPAWN_3D_POSITIONS.length)];
  return { ...sp };
}

function randomItemPosition3D(): { x: number; y: number; z: number } {
  return {
    x: Math.round((Math.random() * 40 - 20) * 10) / 10,
    y: 0.6,
    z: Math.round((Math.random() * 40 - 20) * 10) / 10
  };
}

// ── Schemas ──────────────────────────────────────────────────────────────────
export class ItemState extends Schema {
  @type("string") id: string = "";
  @type("string") type: string = "";
  @type("number") x: number = 0;
  @type("number") y: number = 0.6;
  @type("number") z: number = 0;
  @type("boolean") active: boolean = true;
}

export class PlayerState extends Schema {
  @type("string") id: string = "";
  @type("string") name: string = "Player";
  @type("number") x: number = 0;
  @type("number") y: number = 0.5;
  @type("number") z: number = 0;
  @type("number") rotY: number = 0;
  @type("string") role: string = "runner"; // "tagger" | "runner"
  @type("boolean") frozen: boolean = false;
  @type("boolean") isRescuing: boolean = false;
  @type("boolean") hasShield: boolean = false;
  @type("number") speedMultiplier: number = 1.0;
  @type("string") heldItem: string = "";
  @type("boolean") stunned: boolean = false;
  @type("boolean") connected: boolean = true;
  @type("number") freezeCount: number = 0;
  @type("number") rescueCount: number = 0;
}

export class GameState extends Schema {
  @type("string") phase: string = "lobby"; // "lobby" | "playing" | "ended"
  @type("number") timeLeft: number = 165; // 02:45
  @type("string") winner: string = "";
  @type("string") roomCode: string = "";
  @type("string") roomName: string = "Freeze Tag 3D Room";
  @type("string") hostId: string = "";
  @type("number") currentRound: number = 1;
  @type("number") maxRounds: number = 3;
  @type("string") mapName: string = "CASTLE";
  @type("number") runnersScore: number = 0;
  @type("number") taggersScore: number = 0;
  @type({ map: PlayerState }) players = new MapSchema<PlayerState>();
  @type({ map: ItemState }) items = new MapSchema<ItemState>();
}

interface GameRoomMetadata {
  roomCode: string;
  roomName: string;
  maxPlayers: number;
  rounds: number;
  map: string;
  hasStarted: boolean;
}

interface GameRoomOptions {
  state: GameState;
  metadata: GameRoomMetadata;
}

// ── 3D GameRoom ─────────────────────────────────────────────────────────────
export class GameRoom extends Room<GameRoomOptions> {
  maxClients = 8;
  private timerInterval: ReturnType<typeof setInterval> | null = null;
  private itemSpawnInterval: ReturnType<typeof setInterval> | null = null;
  private itemCounter = 0;
  private tagCooldowns: Map<string, number> = new Map();

  private getGameState(): GameState {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    return (this as any).state as GameState;
  }

  private setGameState(s: GameState) {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (this as any).setState(s);
  }

  private updateMeta(m: Partial<GameRoomMetadata>) {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const current = (this as any).metadata || {};
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    (this as any).setMetadata({ ...current, ...m });
  }

  onCreate(options: Record<string, unknown>) {
    const initialState = new GameState();
    
    // Among Us style 6-character clean PIN code
    const CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    const generateCode = () =>
      Array.from({ length: 6 }, () => CHARS[Math.floor(Math.random() * CHARS.length)]).join("");
    
    const code = String(options["roomCode"] || generateCode()).toUpperCase();
    const rName = String(options["roomName"] || `Room ${code}`);
    const maxP = Math.max(4, Math.min(8, Number(options["maxPlayers"]) || 8));
    const rounds = Math.max(1, Math.min(5, Number(options["rounds"]) || 3));
    const map = String(options["map"] || "CASTLE");

    this.roomId = code;
    this.maxClients = maxP;
    initialState.roomCode = code;
    initialState.roomName = rName;
    initialState.maxRounds = rounds;
    initialState.mapName = map;

    this.setGameState(initialState);
    this.updateMeta({
      roomCode: code,
      roomName: rName,
      maxPlayers: maxP,
      rounds: rounds,
      map: map,
      hasStarted: false
    });

    console.log(`[GameRoom 3D] Created Room: ${code} ("${rName}") Max: ${maxP}`);

    // ── Incoming Messages from Godot / Web Client ───────────────────────────
    
    // 1. Host settings update in lobby
    this.onMessage("update_settings", (client: Client, data: { maxPlayers?: number; rounds?: number; map?: string }) => {
      const gs = this.getGameState();
      if (client.sessionId !== gs.hostId) return;
      if (data.maxPlayers) {
        this.maxClients = Math.max(4, Math.min(8, data.maxPlayers));
      }
      if (data.rounds) {
        gs.maxRounds = Math.max(1, Math.min(5, data.rounds));
      }
      if (data.map) {
        gs.mapName = data.map;
      }
      this.updateMeta({
        maxPlayers: this.maxClients,
        rounds: gs.maxRounds,
        map: gs.mapName
      });
      this.broadcast("settings_updated", {
        maxPlayers: this.maxClients,
        rounds: gs.maxRounds,
        map: gs.mapName
      });
    });

    // 2. Start Game
    this.onMessage("start_game", (client: Client) => {
      const gs = this.getGameState();
      if (client.sessionId !== gs.hostId) return;
      this.startRound();
    });

    // 3. 3D Movement Sync
    this.onMessage("move", (client: Client, data: { x: number; y: number; z: number; rotY?: number }) => {
      const gs = this.getGameState();
      const player = gs.players.get(client.sessionId);
      if (!player || gs.phase !== "playing") return;
      if (player.frozen || player.stunned) return;

      player.x = data.x;
      player.y = data.y;
      player.z = data.z;
      if (typeof data.rotY === "number") {
        player.rotY = data.rotY;
      }

      // Real-time broadcast for smooth client interpolation
      this.broadcast("player_moved", {
        id: client.sessionId,
        x: player.x,
        y: player.y,
        z: player.z,
        rotY: player.rotY
      });
    });

    // 4. Tag Player (Tagger hits Runner)
    this.onMessage("tag_player", (client: Client, data: { victimId: string }) => {
      const gs = this.getGameState();
      if (gs.phase !== "playing") return;
      const tagger = gs.players.get(client.sessionId);
      const victim = gs.players.get(data.victimId);
      if (!tagger || !victim) return;
      if (tagger.role !== "tagger" || victim.role !== "runner" || victim.frozen) return;

      // Tag cooldown to prevent double tagging
      const now = Date.now();
      const lastTag = this.tagCooldowns.get(tagger.id) || 0;
      if (now - lastTag < 1000) return;
      this.tagCooldowns.set(tagger.id, now);

      if (victim.hasShield) {
        victim.hasShield = false;
        this.broadcast("shield_broken", { playerId: victim.id });
        this.broadcast("chat_message", { msg: `🛡️ ${victim.name}'s shield absorbed the tag!` });
      } else {
        victim.frozen = true;
        victim.isRescuing = false;
        tagger.freezeCount += 1;
        this.broadcast("player_tagged", {
          taggerId: tagger.id,
          taggerName: tagger.name,
          victimId: victim.id,
          victimName: victim.name
        });
        this.broadcast("chat_message", { msg: `❄️ ${tagger.name} froze ${victim.name}!` });
        this.checkEndCondition(gs);
      }
    });

    // 5. Rescue Player (Runner thaws frozen Runner)
    this.onMessage("rescue_player", (client: Client, data: { victimId: string }) => {
      const gs = this.getGameState();
      if (gs.phase !== "playing") return;
      const rescuer = gs.players.get(client.sessionId);
      const victim = gs.players.get(data.victimId);
      if (!rescuer || !victim) return;
      if (rescuer.role !== "runner" || rescuer.frozen || victim.role !== "runner" || !victim.frozen) return;

      victim.frozen = false;
      rescuer.rescueCount += 1;
      this.broadcast("player_rescued", {
        rescuerId: rescuer.id,
        rescuerName: rescuer.name,
        victimId: victim.id,
        victimName: victim.name
      });
      this.broadcast("chat_message", { msg: `🔥 ${rescuer.name} rescued ${victim.name}!` });
    });

    // 6. Rescuing proximity signal
    this.onMessage("rescuing_state", (client: Client, data: { isRescuing: boolean }) => {
      const p = this.getGameState().players.get(client.sessionId);
      if (p && !p.frozen && p.role === "runner") {
        p.isRescuing = Boolean(data.isRescuing);
        this.broadcast("player_rescuing", { playerId: p.id, isRescuing: p.isRescuing });
      }
    });

    // 7. Pick up item in arena
    this.onMessage("pick_item", (client: Client, data: { itemId: string }) => {
      const gs = this.getGameState();
      if (gs.phase !== "playing") return;
      const player = gs.players.get(client.sessionId);
      const item = gs.items.get(data.itemId);
      if (!player || !item || !item.active) return;
      if (player.heldItem !== "") return; // Single item slot!

      item.active = false;
      player.heldItem = item.type;
      gs.items.delete(data.itemId);

      this.broadcast("item_picked", {
        playerId: player.id,
        playerName: player.name,
        itemId: item.id,
        itemType: item.type
      });
      this.broadcast("chat_message", { msg: `🎒 ${player.name} picked up ${item.type.toUpperCase()}!` });
    });

    // 8. Use single held item [E]
    this.onMessage("use_item", (client: Client, _data: unknown) => {
      const gs = this.getGameState();
      if (gs.phase !== "playing") return;
      const player = gs.players.get(client.sessionId);
      if (!player || player.heldItem === "") return;

      const itemType = player.heldItem as ItemType;
      player.heldItem = "";

      this.applyItemEffect(gs, player, itemType);
    });

    // 9. Client exit / surrender
    this.onMessage("player_exit", (client: Client) => {
      this.handlePlayerLeave(client.sessionId);
    });
  }

  onJoin(client: Client, options: Record<string, unknown>) {
    const gs = this.getGameState();
    const player = new PlayerState();
    player.id = client.sessionId;
    player.name = String(options["playerName"] || `Player ${this.clients.length}`);
    
    const sp = randomSpawn3D();
    player.x = sp.x;
    player.y = sp.y;
    player.z = sp.z;

    if (this.clients.length === 1) {
      gs.hostId = client.sessionId;
    }

    gs.players.set(client.sessionId, player);

    this.broadcast("player_joined", {
      id: player.id,
      name: player.name,
      isHost: client.sessionId === gs.hostId,
      playersCount: this.clients.length,
      maxPlayers: this.maxClients
    });

    console.log(`[GameRoom 3D] ${player.name} (${client.sessionId}) joined ${gs.roomCode}`);
  }

  onLeave(client: Client, _code?: number) {
    this.handlePlayerLeave(client.sessionId);
  }

  onDispose() {
    this.stopTimers();
    console.log(`[GameRoom 3D] Room ${this.getGameState().roomCode} disposed.`);
  }

  // ── Round Management ───────────────────────────────────────────────────────
  private startRound() {
    const gs = this.getGameState();
    gs.phase = "playing";
    gs.timeLeft = 165; // 02:45
    this.updateMeta({ hasStarted: true });

    this.assignRoles(gs);
    this.placePlayersOn3DMap(gs);
    this.spawnInitialItems(gs);
    this.startTimer(gs);
    this.startItemSpawner(gs);

    const playersList: Array<{ id: string; name: string; role: string; x: number; y: number; z: number }> = [];
    gs.players.forEach(p => {
      playersList.push({
        id: p.id,
        name: p.name,
        role: p.role,
        x: p.x,
        y: p.y,
        z: p.z
      });
    });

    this.broadcast("round_started", {
      round: gs.currentRound,
      maxRounds: gs.maxRounds,
      timeLeft: gs.timeLeft,
      players: playersList
    });
    this.broadcast("chat_message", { msg: `🔥 Round ${gs.currentRound}/${gs.maxRounds} started!` });
  }

  private assignRoles(gs: GameState) {
    const playerIds = Array.from(gs.players.keys());
    const taggerIdx = Math.floor(Math.random() * playerIds.length);

    playerIds.forEach((id, i) => {
      const p = gs.players.get(id)!;
      p.role = i === taggerIdx ? "tagger" : "runner";
      p.frozen = false;
      p.isRescuing = false;
      p.hasShield = false;
      p.speedMultiplier = p.role === "tagger" ? 1.1 : 1.0;
      p.stunned = false;
      p.heldItem = "";
    });
  }

  private placePlayersOn3DMap(gs: GameState) {
    let idx = 0;
    gs.players.forEach((p) => {
      const sp = SPAWN_3D_POSITIONS[idx % SPAWN_3D_POSITIONS.length];
      p.x = sp.x;
      p.y = sp.y;
      p.z = sp.z;
      idx++;
    });
  }

  private spawnInitialItems(gs: GameState) {
    gs.items.clear();
    const itemTypes: ItemType[] = ["speed", "shield", "heater", "banana", "vortex"];
    for (let i = 0; i < 4; i++) {
      const t = itemTypes[Math.floor(Math.random() * itemTypes.length)];
      const pos = randomItemPosition3D();
      this.spawnItem(t, pos.x, pos.y, pos.z);
    }
  }

  private spawnItem(type: ItemType, x: number, y: number, z: number) {
    const gs = this.getGameState();
    const item = new ItemState();
    item.id = `item_${++this.itemCounter}`;
    item.type = type;
    item.x = x;
    item.y = y;
    item.z = z;
    item.active = true;
    gs.items.set(item.id, item);

    this.broadcast("item_spawned", {
      id: item.id,
      type: item.type,
      x: item.x,
      y: item.y,
      z: item.z
    });
  }

  private startTimer(gs: GameState) {
    if (this.timerInterval) clearInterval(this.timerInterval);
    this.timerInterval = setInterval(() => {
      if (gs.phase !== "playing") {
        this.stopTimers();
        return;
      }
      gs.timeLeft -= 1;
      if (gs.timeLeft % 5 === 0 || gs.timeLeft <= 10) {
        this.broadcast("time_sync", { timeLeft: gs.timeLeft });
      }
      if (gs.timeLeft <= 0) {
        this.endRound(gs, "RUNNERS", "Time Ran Out");
      }
    }, 1000);
  }

  private startItemSpawner(gs: GameState) {
    if (this.itemSpawnInterval) clearInterval(this.itemSpawnInterval);
    this.itemSpawnInterval = setInterval(() => {
      if (gs.phase !== "playing") return;
      if (gs.items.size < 6) {
        const types: ItemType[] = ["speed", "shield", "heater", "banana", "vortex"];
        const t = types[Math.floor(Math.random() * types.length)];
        const pos = randomItemPosition3D();
        this.spawnItem(t, pos.x, pos.y, pos.z);
      }
    }, 9000);
  }

  private stopTimers() {
    if (this.timerInterval) {
      clearInterval(this.timerInterval);
      this.timerInterval = null;
    }
    if (this.itemSpawnInterval) {
      clearInterval(this.itemSpawnInterval);
      this.itemSpawnInterval = null;
    }
  }

  private checkEndCondition(gs: GameState) {
    const activeRunners: PlayerState[] = [];
    gs.players.forEach(p => {
      if (p.role === "runner" && !p.frozen) {
        activeRunners.push(p);
      }
    });

    if (activeRunners.length === 0) {
      this.endRound(gs, "TAGGERS", "All Runners Frozen");
    }
  }

  private endRound(gs: GameState, winner: "TAGGERS" | "RUNNERS", reason: string) {
    if (gs.phase === "ended") return;
    gs.phase = "ended";
    this.stopTimers();

    if (winner === "TAGGERS") {
      gs.taggersScore += 1;
    } else {
      gs.runnersScore += 1;
    }

    // Determine MVP
    let bestPlayer: PlayerState | null = null;
    let maxPoints = -1;
    gs.players.forEach(p => {
      const pts = p.freezeCount * 2 + p.rescueCount * 2;
      if (pts > maxPoints) {
        maxPoints = pts;
        bestPlayer = p;
      }
    });

    const isMatchOver = gs.currentRound >= gs.maxRounds;

    const mvpData = bestPlayer ? {
      id: (bestPlayer as PlayerState).id,
      name: (bestPlayer as PlayerState).name,
      freezeCount: (bestPlayer as PlayerState).freezeCount,
      rescueCount: (bestPlayer as PlayerState).rescueCount
    } : null;

    this.broadcast("round_ended", {
      winner,
      reason,
      runnersScore: gs.runnersScore,
      taggersScore: gs.taggersScore,
      currentRound: gs.currentRound,
      maxRounds: gs.maxRounds,
      isMatchOver,
      mvp: mvpData
    });

    if (isMatchOver) {
      this.broadcast("chat_message", { msg: `🏆 Match Over! Final: Runners ${gs.runnersScore} - Taggers ${gs.taggersScore}` });
    }
  }

  // ── Item Effects ──────────────────────────────────────────────────────────
  private applyItemEffect(gs: GameState, player: PlayerState, itemType: ItemType) {
    this.broadcast("item_used", {
      playerId: player.id,
      playerName: player.name,
      type: itemType
    });

    switch (itemType) {
      case "speed":
        player.speedMultiplier = 1.4;
        this.broadcast("chat_message", { msg: `⚡ ${player.name} activated SPEED BOOST!` });
        setTimeout(() => {
          player.speedMultiplier = player.role === "tagger" ? 1.1 : 1.0;
        }, 6000);
        break;

      case "shield":
        player.hasShield = true;
        this.broadcast("chat_message", { msg: `🛡️ ${player.name} activated SHIELD!` });
        setTimeout(() => {
          player.hasShield = false;
        }, 10000);
        break;

      case "heater":
        if (player.frozen) {
          player.frozen = false;
          this.broadcast("player_unfrozen", { playerId: player.id });
          this.broadcast("chat_message", { msg: `🔥 ${player.name} melted themselves with Heater!` });
        } else {
          // Unfreeze random nearby runner
          let thawed = false;
          gs.players.forEach(p => {
            if (!thawed && p.role === "runner" && p.frozen) {
              p.frozen = false;
              thawed = true;
              this.broadcast("player_unfrozen", { playerId: p.id });
              this.broadcast("chat_message", { msg: `🔥 ${player.name} thawed ${p.name} with Heater!` });
            }
          });
        }
        break;

      case "banana":
        // Drops banana trap at player's 3D position
        this.broadcast("banana_placed", {
          x: player.x,
          y: player.y,
          z: player.z
        });
        this.broadcast("chat_message", { msg: `🍌 ${player.name} placed a Banana Trap!` });
        break;

      case "vortex":
        // Creates black hole vortex at player's 3D position
        this.broadcast("vortex_spawned", {
          x: player.x,
          y: player.y,
          z: player.z
        });
        this.broadcast("chat_message", { msg: `🌀 ${player.name} opened a Black Hole Vortex!` });
        break;
    }
  }

  private handlePlayerLeave(sessionId: string) {
    const gs = this.getGameState();
    const player = gs.players.get(sessionId);
    if (!player) return;

    const leavingName = player.name;
    const leavingRole = player.role;
    gs.players.delete(sessionId);

    this.broadcast("player_left", {
      id: sessionId,
      name: leavingName,
      playersCount: gs.players.size
    });

    if (sessionId === gs.hostId) {
      // Reassign host
      const firstKey = gs.players.keys().next().value;
      if (firstKey) {
        gs.hostId = firstKey;
        this.broadcast("host_changed", { newHostId: firstKey });
      }
    }

    if (gs.phase === "playing") {
      if (leavingRole === "tagger") {
        this.endRound(gs, "RUNNERS", `Tagger ${leavingName} left match`);
      } else {
        this.checkEndCondition(gs);
      }
    }
  }
}
