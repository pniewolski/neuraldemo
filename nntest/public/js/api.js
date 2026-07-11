/**
 * api.js
 * ==================================================================
 * Cienka warstwa komunikacji z backendem (zapis/odczyt danych).
 * Backend służy WYŁĄCZNIE do przechowywania próbek treningowych.
 * ==================================================================
 */

const api = {
  /** Zapisuje jedną próbkę treningową (obrazek + etykieta). */
  async saveSample(label, pixels) {
    const res = await fetch('/api/samples', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ label, pixels }),
    });
    if (!res.ok) throw new Error((await res.json()).error || 'Błąd zapisu');
    return res.json();
  },

  /** Pobiera wszystkie próbki treningowe. */
  async getSamples() {
    const res = await fetch('/api/samples');
    return (await res.json()).samples;
  },

  /** Pobiera statystyki (ile obrazków na etykietę). */
  async getStats() {
    const res = await fetch('/api/stats');
    return (await res.json()).stats;
  },

  /** Kasuje wszystkie dane treningowe. */
  async clearAll() {
    await fetch('/api/samples', { method: 'DELETE' });
  },
};

window.api = api;

