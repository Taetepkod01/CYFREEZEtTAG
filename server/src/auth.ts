import fs from "fs";
import path from "path";
import crypto from "crypto";

// ── Firebase Project Configuration ──────────────────────────────────────────
export const FIREBASE_CONFIG = {
  projectId: "cyfreezetag-3d-game",
  apiKey: "AIzaSyA1dfz0Z82id36JnSzgaZyOsnNhn2ninHc",
  authDomain: "cyfreezetag-3d-game.firebaseapp.com"
};

// ── User Profile Interface ──────────────────────────────────────────────────
export interface UserProfile {
  uid: string;
  email: string;
  displayName: string;
  level: number;
  exp: number;
  maxExp: number;
  coins: number;
  matchesPlayed: number;
  matchesWon: number;
  totalTags: number;
  totalRescues: number;
  isGuest: boolean;
  createdAt: number;
  lastLogin: number;
}

interface StoredAccount {
  uid: string;
  email: string;
  passwordHash: string;
  salt: string;
  profile: UserProfile;
}

// Local storage path for persistence
const DATA_DIR = path.join(__dirname, "../data");
const USERS_FILE = path.join(DATA_DIR, "users.json");

// In-Memory cache of profiles & accounts
const accountsMap = new Map<string, StoredAccount>(); // keyed by email
const usersByIdMap = new Map<string, UserProfile>();  // keyed by uid

function ensureDataDir() {
  if (!fs.existsSync(DATA_DIR)) {
    fs.mkdirSync(DATA_DIR, { recursive: true });
  }
}

function loadAccountsFromDisk() {
  ensureDataDir();
  if (fs.existsSync(USERS_FILE)) {
    try {
      const raw = fs.readFileSync(USERS_FILE, "utf-8");
      const list: StoredAccount[] = JSON.parse(raw);
      list.forEach(acc => {
        accountsMap.set(acc.email.toLowerCase(), acc);
        usersByIdMap.set(acc.uid, acc.profile);
      });
      console.log(`[Auth] Loaded ${accountsMap.size} user accounts from disk.`);
    } catch (err) {
      console.error("[Auth] Error reading users.json:", err);
    }
  }
}

function saveAccountsToDisk() {
  ensureDataDir();
  try {
    const list = Array.from(accountsMap.values());
    fs.writeFileSync(USERS_FILE, JSON.stringify(list, null, 2), "utf-8");
  } catch (err) {
    console.error("[Auth] Error saving users.json:", err);
  }
}

// Initial load
loadAccountsFromDisk();

// ── Level & EXP Progression Curve ───────────────────────────────────────────
// Level 1: 100 EXP
// Level 2: 150 EXP (Total 250)
// Level 3: 200 EXP (Total 450)
// Level L: L * 100 + (L - 1) * 50
export function getMaxExpForLevel(level: number): number {
  return Math.max(100, Math.floor(level * 100 + (level - 1) * 50));
}

export function addExpAndCoins(
  profile: UserProfile,
  expGain: number,
  coinsGain: number
): {
  leveledUp: boolean;
  levelBefore: number;
  levelAfter: number;
  expGained: number;
  coinsGained: number;
} {
  const levelBefore = profile.level;
  profile.exp += Math.max(0, expGain);
  profile.coins += Math.max(0, coinsGain);

  let leveledUp = false;
  while (profile.exp >= profile.maxExp) {
    profile.exp -= profile.maxExp;
    profile.level += 1;
    profile.maxExp = getMaxExpForLevel(profile.level);
    leveledUp = true;
  }

  saveUserProfile(profile);

  return {
    leveledUp,
    levelBefore,
    levelAfter: profile.level,
    expGained: expGain,
    coinsGained: coinsGain
  };
}

// ── Password Hashing Helpers ────────────────────────────────────────────────
function hashPassword(password: string): { hash: string; salt: string } {
  const salt = crypto.randomBytes(16).toString("hex");
  const hash = crypto.pbkdf2Sync(password, salt, 1000, 64, "sha512").toString("hex");
  return { hash, salt };
}

function verifyPassword(password: string, salt: string, expectedHash: string): boolean {
  const hash = crypto.pbkdf2Sync(password, salt, 1000, 64, "sha512").toString("hex");
  return hash === expectedHash;
}

// ── Firebase REST API Helpers ───────────────────────────────────────────────
async function tryFirebaseAuthRegister(email: string, pass: string): Promise<string | null> {
  try {
    const url = `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${FIREBASE_CONFIG.apiKey}`;
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password: pass, returnSecureToken: true })
    });
    if (res.ok) {
      const data: any = await res.json();
      return data.localId || null;
    }
  } catch (_e) {}
  return null;
}

async function tryFirebaseAuthLogin(email: string, pass: string): Promise<string | null> {
  try {
    const url = `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${FIREBASE_CONFIG.apiKey}`;
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password: pass, returnSecureToken: true })
    });
    if (res.ok) {
      const data: any = await res.json();
      return data.localId || null;
    }
  } catch (_e) {}
  return null;
}

// ── Public Authentication API ───────────────────────────────────────────────
export async function registerUser(email: string, pass: string, displayName: string): Promise<{ success: boolean; user?: UserProfile; message?: string }> {
  const cleanEmail = String(email || "").trim().toLowerCase();
  const cleanName = String(displayName || "").trim().slice(0, 16) || "Player";
  
  if (!cleanEmail || !cleanEmail.includes("@")) {
    return { success: false, message: "Invalid email format." };
  }
  if (!pass || pass.length < 6) {
    return { success: false, message: "Password must be at least 6 characters." };
  }

  if (accountsMap.has(cleanEmail)) {
    return { success: false, message: "An account with this email already exists." };
  }

  // 1. Attempt Firebase Auth registration
  let fbUid = await tryFirebaseAuthRegister(cleanEmail, pass);
  const uid = fbUid || `user_${crypto.randomUUID()}`;

  // 2. Create Profile with Starter Bonus
  const { hash, salt } = hashPassword(pass);
  const now = Date.now();
  const profile: UserProfile = {
    uid,
    email: cleanEmail,
    displayName: cleanName,
    level: 1,
    exp: 0,
    maxExp: getMaxExpForLevel(1),
    coins: 100, // 🪙 Starter Bonus!
    matchesPlayed: 0,
    matchesWon: 0,
    totalTags: 0,
    totalRescues: 0,
    isGuest: false,
    createdAt: now,
    lastLogin: now
  };

  const account: StoredAccount = {
    uid,
    email: cleanEmail,
    passwordHash: hash,
    salt,
    profile
  };

  accountsMap.set(cleanEmail, account);
  usersByIdMap.set(uid, profile);
  saveAccountsToDisk();

  console.log(`[Auth] Registered new user: ${cleanName} (${cleanEmail}, uid: ${uid})`);
  return { success: true, user: profile };
}

export async function loginUser(email: string, pass: string): Promise<{ success: boolean; user?: UserProfile; message?: string }> {
  const cleanEmail = String(email || "").trim().toLowerCase();
  
  if (!cleanEmail || !pass) {
    return { success: false, message: "Email and password are required." };
  }

  // 1. Check local persistent store
  const account = accountsMap.get(cleanEmail);
  if (account) {
    if (!verifyPassword(pass, account.salt, account.passwordHash)) {
      return { success: false, message: "Incorrect password." };
    }
    account.profile.lastLogin = Date.now();
    saveAccountsToDisk();
    return { success: true, user: account.profile };
  }

  // 2. If not local, try Firebase Auth directly
  const fbUid = await tryFirebaseAuthLogin(cleanEmail, pass);
  if (fbUid) {
    const existing = usersByIdMap.get(fbUid);
    if (existing) {
      existing.lastLogin = Date.now();
      saveAccountsToDisk();
      return { success: true, user: existing };
    }
    // Create new profile for Firebase user
    const { hash, salt } = hashPassword(pass);
    const now = Date.now();
    const profile: UserProfile = {
      uid: fbUid,
      email: cleanEmail,
      displayName: cleanEmail.split("@")[0] || "Player",
      level: 1,
      exp: 0,
      maxExp: getMaxExpForLevel(1),
      coins: 100,
      matchesPlayed: 0,
      matchesWon: 0,
      totalTags: 0,
      totalRescues: 0,
      isGuest: false,
      createdAt: now,
      lastLogin: now
    };
    const newAcc: StoredAccount = { uid: fbUid, email: cleanEmail, passwordHash: hash, salt, profile };
    accountsMap.set(cleanEmail, newAcc);
    usersByIdMap.set(fbUid, profile);
    saveAccountsToDisk();
    return { success: true, user: profile };
  }

  return { success: false, message: "Account not found or invalid credentials." };
}

export function guestLogin(displayName: string, existingUid?: string): UserProfile {
  const cleanName = String(displayName || "Guest").trim().slice(0, 16) || "Guest";
  
  if (existingUid && usersByIdMap.has(existingUid)) {
    const existing = usersByIdMap.get(existingUid)!;
    existing.displayName = cleanName;
    existing.lastLogin = Date.now();
    saveUserProfile(existing);
    return existing;
  }

  const uid = existingUid || `guest_${Math.random().toString(36).substring(2, 9)}`;
  const now = Date.now();
  const profile: UserProfile = {
    uid,
    email: "",
    displayName: cleanName,
    level: 1,
    exp: 0,
    maxExp: getMaxExpForLevel(1),
    coins: 50, // Guest starter coins
    matchesPlayed: 0,
    matchesWon: 0,
    totalTags: 0,
    totalRescues: 0,
    isGuest: true,
    createdAt: now,
    lastLogin: now
  };

  usersByIdMap.set(uid, profile);
  return profile;
}

export function getUserProfile(uid: string): UserProfile | null {
  return usersByIdMap.get(uid) || null;
}

export function saveUserProfile(profile: UserProfile): void {
  usersByIdMap.set(profile.uid, profile);
  if (profile.email && accountsMap.has(profile.email.toLowerCase())) {
    const acc = accountsMap.get(profile.email.toLowerCase())!;
    acc.profile = profile;
  }
  saveAccountsToDisk();
}
