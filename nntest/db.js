/**
 * db.js
 * ------------------------------------------------------------------
 * Warstwa dostępu do danych (magazyn próbek treningowych).
 *
 * Zależy nam na "lekkiej bazie danych w rodzaju SQLite". Używamy więc
 * biblioteki `better-sqlite3` (bardzo prosty, synchroniczny sterownik
 * SQLite). Jest to natywny moduł, który czasem trzeba skompilować.
 *
 * Aby aplikacja edukacyjna ZAWSZE się uruchomiła (nawet gdy ktoś nie
 * ma narzędzi do kompilacji), przygotowaliśmy AWARYJNY magazyn oparty
 * na zwykłym pliku JSON. Interfejs obu magazynów jest identyczny,
 * dzięki czemu reszta serwera nie musi wiedzieć, którego używamy.
 *
 * Każda "próbka" (sample) to jeden narysowany obrazek:
 *   - id      : liczba,
 *   - label   : etykieta (co przedstawia obrazek, np. "A", "serce"),
 *   - pixels  : tablica 32*32 = 1024 wartości z zakresu 0..1
 *               (0 = pusty piksel, 1 = w pełni zamalowany).
 * ------------------------------------------------------------------
 */

const fs = require('fs');
const path = require('path');

const DATA_DIR = path.join(__dirname, 'data');
if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });

/* =========================================================================
 * Wariant 1: prawdziwa baza SQLite (better-sqlite3)
 * ========================================================================= */
function createSqliteStore() {
  // Jeżeli modułu nie ma / nie da się załadować, rzucamy wyjątek,
  // a wywołujący przełączy się na magazyn plikowy.
  const Database = require('better-sqlite3');
  const db = new Database(path.join(DATA_DIR, 'samples.db'));

  // Tworzymy tabelę, jeśli jeszcze nie istnieje.
  db.exec(`
    CREATE TABLE IF NOT EXISTS samples (
      id     INTEGER PRIMARY KEY AUTOINCREMENT,
      label  TEXT NOT NULL,
      pixels TEXT NOT NULL          -- tablica 1024 liczb zapisana jako JSON
    );
  `);

  return {
    kind: 'sqlite',

    addSample(label, pixels) {
      const info = db
        .prepare('INSERT INTO samples (label, pixels) VALUES (?, ?)')
        .run(label, JSON.stringify(pixels));
      return { id: info.lastInsertRowid, label };
    },

    getAllSamples() {
      const rows = db.prepare('SELECT id, label, pixels FROM samples').all();
      return rows.map((r) => ({
        id: r.id,
        label: r.label,
        pixels: JSON.parse(r.pixels),
      }));
    },

    // Zestawienie: ile obrazków mamy dla każdej etykiety.
    getLabelStats() {
      return db
        .prepare('SELECT label, COUNT(*) AS count FROM samples GROUP BY label ORDER BY label')
        .all();
    },

    clear() {
      db.prepare('DELETE FROM samples').run();
    },
  };
}

/* =========================================================================
 * Wariant 2: awaryjny magazyn oparty na pliku JSON
 * ========================================================================= */
function createJsonStore() {
  const file = path.join(DATA_DIR, 'samples.json');
  let state = { nextId: 1, samples: [] };

  if (fs.existsSync(file)) {
    try {
      state = JSON.parse(fs.readFileSync(file, 'utf8'));
    } catch (_) {
      /* uszkodzony plik – zaczynamy od zera */
    }
  }

  const save = () => fs.writeFileSync(file, JSON.stringify(state));

  return {
    kind: 'json',

    addSample(label, pixels) {
      const sample = { id: state.nextId++, label, pixels };
      state.samples.push(sample);
      save();
      return { id: sample.id, label };
    },

    getAllSamples() {
      // zwracamy kopie, aby nikt przypadkiem nie zmodyfikował stanu
      return state.samples.map((s) => ({ ...s, pixels: s.pixels.slice() }));
    },

    getLabelStats() {
      const counts = new Map();
      for (const s of state.samples) {
        counts.set(s.label, (counts.get(s.label) || 0) + 1);
      }
      return [...counts.entries()]
        .map(([label, count]) => ({ label, count }))
        .sort((a, b) => a.label.localeCompare(b.label));
    },

    clear() {
      state = { nextId: 1, samples: [] };
      save();
    },
  };
}

/* =========================================================================
 * Wybór magazynu: najpierw próbujemy SQLite, w razie problemu – JSON.
 * ========================================================================= */
let store;
try {
  store = createSqliteStore();
  console.log('[db] Używam bazy SQLite (better-sqlite3).');
} catch (err) {
  store = createJsonStore();
  console.log(
    '[db] Nie udało się załadować better-sqlite3 – przełączam się na magazyn JSON.\n' +
      '     (Aby użyć prawdziwego SQLite, uruchom "npm install".)'
  );
}

module.exports = store;

