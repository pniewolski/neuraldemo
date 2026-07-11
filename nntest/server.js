/**
 * server.js
 * ------------------------------------------------------------------
 * Bardzo prosty backend w Node.js (Express).
 *
 * Jego JEDYNE zadanie to przechowywanie danych treningowych:
 *   - zapisywanie narysowanych obrazków wraz z etykietą,
 *   - odczytywanie wszystkich obrazków (do nauki sieci),
 *   - podawanie statystyk (ile obrazków na etykietę).
 *
 * Cała "inteligencja" (sieć neuronowa, uczenie, rozpoznawanie i
 * wizualizacja) dzieje się po stronie przeglądarki – patrz katalog
 * `public/js`. Dzięki temu widać w akcji każdy neuron.
 * ------------------------------------------------------------------
 */

const path = require('path');
const express = require('express');
const db = require('./db');

const app = express();
const PORT = process.env.PORT || 3000;

// Pozwalamy na dość duże ciała żądań – obrazek to 1024 liczby.
app.use(express.json({ limit: '2mb' }));

// Serwujemy pliki frontendu (HTML/CSS/JS) z katalogu `public`.
app.use(express.static(path.join(__dirname, 'public')));

/* ----------------------------- API ------------------------------ */

// Zapis pojedynczej próbki treningowej.
app.post('/api/samples', (req, res) => {
  const { label, pixels } = req.body || {};

  // Prosta walidacja danych wejściowych.
  if (typeof label !== 'string' || label.trim() === '') {
    return res.status(400).json({ error: 'Brak etykiety (label).' });
  }
  if (!Array.isArray(pixels) || pixels.length !== 32 * 32) {
    return res.status(400).json({ error: 'Pole pixels musi mieć 1024 wartości.' });
  }

  const saved = db.addSample(label.trim(), pixels);
  res.json({ ok: true, sample: saved });
});

// Pobranie wszystkich próbek (używane przy uczeniu).
app.get('/api/samples', (req, res) => {
  res.json({ samples: db.getAllSamples() });
});

// Statystyki: ile obrazków przypada na każdą etykietę.
app.get('/api/stats', (req, res) => {
  res.json({ stats: db.getLabelStats() });
});

// Wyczyszczenie całej bazy (przydatne przy eksperymentach).
app.delete('/api/samples', (req, res) => {
  db.clear();
  res.json({ ok: true });
});

/* --------------------------- Start ------------------------------ */
app.listen(PORT, () => {
  console.log(`\nSieć neuronowa – aplikacja edukacyjna`);
  console.log(`Otwórz w przeglądarce:  http://localhost:${PORT}\n`);
});

