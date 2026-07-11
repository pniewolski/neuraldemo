/**
 * visualizer.js
 * ==================================================================
 * WIZUALIZACJA SIECI NEURONOWEJ na elemencie <canvas>.
 *
 * Co widzimy na rysunku:
 *   - NEURONY  -> małe kółka ułożone w warstwach (kolumnach),
 *                 wejście pokazujemy jako siatkę 8x8 (zmniejszony obrazek).
 *   - POŁĄCZENIA -> cienkie linie między neuronami sąsiednich warstw.
 *
 * KODOWANIE KOLORAMI (klucz do zrozumienia):
 *   - Tryb "weights" (wagi): kolor linii = WARTOŚĆ WAGI połączenia.
 *       kolor ciepły (pomarańcz/czerwień) = waga dodatnia,
 *       kolor zimny (błękit)             = waga ujemna,
 *       jasność/grubość                  = siła (wartość bezwzględna).
 *   - Tryb "signal" (sygnał): kolor linii = WARTOŚĆ PRZEKAZYWANA
 *       przez połączenie w danej chwili (waga * pobudzenie neuronu).
 *       Kółka neuronów świecą tym jaśniej, im mocniej są pobudzone.
 * ==================================================================
 */

class Visualizer {
  constructor(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.network = null;
    this.layout = null; // pozycje neuronów po obliczeniu układu
  }

  /** Podłącza sieć i wylicza rozmieszczenie neuronów. */
  setNetwork(network) {
    this.network = network;
    this._computeLayout();
  }

  /**
   * Oblicza pozycje (x, y) wszystkich neuronów.
   * Struktura: this.layout[i] = tablica {x, y} dla warstwy i.
   *   warstwa 0 = wejście (siatka 8x8),
   *   kolejne  = warstwy neuronów (kolumny).
   */
  _computeLayout() {
    const W = this.canvas.width;
    const H = this.canvas.height;
    const net = this.network;
    const grid = window.nnConfig.INPUT_GRID; // 8

    this.layout = [];

    // --- Warstwa wejściowa: siatka grid x grid po lewej stronie. ---
    const inputPos = [];
    const cell = Math.min(H, W * 0.28) / grid; // rozmiar oczka siatki
    const gridW = cell * grid;
    const gridLeft = W * 0.10;
    const gridTop = (H - gridW) / 2;
    for (let gy = 0; gy < grid; gy++) {
      for (let gx = 0; gx < grid; gx++) {
        inputPos.push({
          x: gridLeft + gx * cell + cell / 2,
          y: gridTop + gy * cell + cell / 2,
        });
      }
    }
    this.layout.push(inputPos);
    this.inputCell = cell;

    // --- Kolejne warstwy: równomierne kolumny. ---
    // Rezerwujemy prawą część canvasu na warstwy ukryte i wyjściową.
    const numColumns = net.layers.length; // ukryta + wyjściowa
    const firstColX = W * 0.5;
    const lastColX = W * 0.82;
    for (let l = 0; l < numColumns; l++) {
      const count = net.layers[l].length;
      const colX =
        numColumns === 1
          ? firstColX
          : firstColX + ((lastColX - firstColX) * l) / (numColumns - 1);
      const positions = [];
      const usableH = H * 0.85;
      const top = (H - usableH) / 2;
      for (let n = 0; n < count; n++) {
        const y =
          count === 1 ? H / 2 : top + (usableH * n) / (count - 1);
        positions.push({ x: colX, y });
      }
      this.layout.push(positions);
    }
  }

  /**
   * Zamienia wartość t (w przybliżeniu -1..1) na kolor linii.
   * Dodatnie = ciepłe, ujemne = zimne, siła = przezroczystość.
   */
  _valueColor(t) {
    const m = Math.min(1, Math.abs(t));
    const alpha = 0.08 + 0.9 * m;
    if (t >= 0) {
      // ciepły: pomarańczowo-czerwony
      return `rgba(255, ${Math.round(150 - 90 * m)}, 60, ${alpha})`;
    }
    // zimny: błękit
    return `rgba(70, ${Math.round(150 - 60 * m)}, 255, ${alpha})`;
  }

  /** Kolor wypełnienia neuronu w zależności od pobudzenia a (0..1). */
  _activationColor(a) {
    const r = Math.round(40 + 215 * a);
    const g = Math.round(40 + 190 * a);
    const b = Math.round(70 + 20 * a);
    return `rgb(${r}, ${g}, ${b})`;
  }

  /**
   * Główna metoda rysująca.
   * @param {object} opts
   *   opts.mode   – 'weights' (pokaż wagi) lub 'signal' (pokaż sygnał).
   *   opts.reveal – ile warstw sygnału jest "zapalonych" (do animacji
   *                 rozpoznawania krok po kroku). Domyślnie wszystkie.
   */
  draw(opts = {}) {
    if (!this.network || !this.layout) return;
    const mode = opts.mode || 'weights';
    const reveal = opts.reveal ?? this.layout.length; // domyślnie wszystko

    const ctx = this.ctx;
    const net = this.network;

    // Tło.
    ctx.fillStyle = '#0f1226';
    ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);

    // ---------- 1. POŁĄCZENIA (linie) ----------
    // Grupa połączeń l łączy warstwę l z warstwą l+1.
    for (let l = 0; l < net.layers.length; l++) {
      const fromPos = this.layout[l];
      const toPos = this.layout[l + 1];
      const layer = net.layers[l];
      const fromAct = net.activations[l];

      // Czy w tej grupie pokazujemy już płynący sygnał?
      const showSignalHere = mode === 'signal' && l < reveal;

      for (let n = 0; n < layer.length; n++) {
        const neuron = layer[n];
        for (let w = 0; w < neuron.weights.length; w++) {
          let value;
          if (showSignalHere) {
            // Wartość faktycznie przekazywana: waga * pobudzenie źródła.
            value = neuron.weights[w] * fromAct[w];
          } else {
            // Sama waga (stan sieci przed/bez sygnału).
            value = neuron.weights[w];
          }
          // Łagodne skalowanie do zakresu ~-1..1.
          const t = Math.tanh(value * 0.8);

          ctx.strokeStyle = this._valueColor(t);
          ctx.lineWidth = 0.5 + 1.6 * Math.min(1, Math.abs(t));
          ctx.beginPath();
          ctx.moveTo(fromPos[w].x, fromPos[w].y);
          ctx.lineTo(toPos[n].x, toPos[n].y);
          ctx.stroke();
        }
      }
    }

    // ---------- 2. NEURONY (kółka) ----------
    for (let li = 0; li < this.layout.length; li++) {
      const positions = this.layout[li];
      const act = net.activations[li];
      const lit = mode === 'signal' && li <= reveal; // czy pokazać pobudzenie
      const isInput = li === 0;
      const radius = isInput ? this.inputCell * 0.42 : 9;

      for (let n = 0; n < positions.length; n++) {
        const p = positions[n];
        const a = act ? act[n] : 0;

        ctx.beginPath();
        ctx.arc(p.x, p.y, radius, 0, Math.PI * 2);
        // Wejście zawsze pokazuje wartości pikseli; pozostałe zależnie od trybu.
        if (isInput || lit) {
          ctx.fillStyle = this._activationColor(a);
        } else {
          ctx.fillStyle = '#2a2f52';
        }
        ctx.fill();
        ctx.lineWidth = 1;
        ctx.strokeStyle = 'rgba(255,255,255,0.25)';
        ctx.stroke();
      }
    }

    // ---------- 3. PODPISY WARSTW ----------
    ctx.fillStyle = 'rgba(230,230,245,0.85)';
    ctx.font = '13px system-ui, sans-serif';
    ctx.textAlign = 'center';
    const grid = window.nnConfig.INPUT_GRID;
    ctx.fillText(
      `WEJŚCIE (${grid}x${grid})`,
      this.layout[0][0].x + this.inputCell * (grid / 2 - 0.5),
      20
    );
    if (net.layers.length >= 2) {
      const hx = this.layout[1][0].x;
      ctx.fillText('WARSTWA UKRYTA', hx, 20);
    }
    const outLayerIndex = this.layout.length - 1;
    const ox = this.layout[outLayerIndex][0].x;
    ctx.fillText('WYJŚCIE', ox, 20);

    // ---------- 4. ETYKIETY WYJŚCIA ----------
    // Obok każdego neuronu wyjściowego piszemy jego etykietę i pobudzenie.
    const outPos = this.layout[outLayerIndex];
    const outAct = net.activations[outLayerIndex];
    ctx.textAlign = 'left';
    ctx.font = '13px system-ui, sans-serif';
    for (let n = 0; n < outPos.length; n++) {
      const p = outPos[n];
      const a = outAct ? outAct[n] : 0;
      const showVal = mode === 'signal' && reveal >= outLayerIndex;
      const text = showVal
        ? `${net.labels[n]}  (${a.toFixed(2)})`
        : `${net.labels[n]}`;
      ctx.fillStyle = showVal
        ? `rgba(255,255,255,${0.4 + 0.6 * a})`
        : 'rgba(230,230,245,0.8)';
      ctx.fillText(text, p.x + 16, p.y + 4);
    }
  }
}

window.Visualizer = Visualizer;


