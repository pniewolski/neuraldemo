/**
 * editor.js
 * ==================================================================
 * PROSTY EDYTOR OBRAZKÓW 32x32.
 *
 * Rysujemy myszką (lub palcem) na siatce 32x32 pikseli. Każdy piksel
 * ma wartość 0..1 (odcień szarości). Używamy miękkiego "pędzla", aby
 * rysowanie było przyjemne, a dane trochę bardziej naturalne.
 *
 * Ta sama klasa służy w dwóch miejscach:
 *   - przy generowaniu danych treningowych,
 *   - przy rozpoznawaniu (rysujemy znak do rozpoznania).
 * ==================================================================
 */

class PixelEditor {
  /**
   * @param {HTMLCanvasElement} canvas – element canvas do rysowania.
   */
  constructor(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.size = 32; // siatka 32x32
    this.pixels = new Array(this.size * this.size).fill(0);

    // Ile pikseli ekranu przypada na jeden piksel obrazka.
    this.scale = canvas.width / this.size;

    this.drawing = false;
    this.erasing = false;

    this._bindEvents();
    this.render();
  }

  _bindEvents() {
    const start = (e) => {
      this.drawing = true;
      // Prawy przycisk lub Shift = gumka.
      this.erasing = e.button === 2 || e.shiftKey;
      this._paintAt(e);
    };
    const move = (e) => {
      if (this.drawing) this._paintAt(e);
    };
    const end = () => {
      this.drawing = false;
    };

    this.canvas.addEventListener('mousedown', start);
    this.canvas.addEventListener('mousemove', move);
    window.addEventListener('mouseup', end);
    // Blokujemy menu kontekstowe, by prawy przycisk mógł być gumką.
    this.canvas.addEventListener('contextmenu', (e) => e.preventDefault());

    // Obsługa dotyku (tablety/telefony).
    this.canvas.addEventListener('touchstart', (e) => {
      e.preventDefault();
      this.drawing = true;
      this.erasing = false;
      this._paintAt(e.touches[0]);
    });
    this.canvas.addEventListener('touchmove', (e) => {
      e.preventDefault();
      if (this.drawing) this._paintAt(e.touches[0]);
    });
    window.addEventListener('touchend', end);
  }

  /** Zamienia pozycję kursora na współrzędne piksela i maluje pędzlem. */
  _paintAt(e) {
    const rect = this.canvas.getBoundingClientRect();
    // Uwzględniamy ewentualne przeskalowanie canvasu przez CSS.
    const scaleX = this.canvas.width / rect.width;
    const scaleY = this.canvas.height / rect.height;
    const px = ((e.clientX - rect.left) * scaleX) / this.scale;
    const py = ((e.clientY - rect.top) * scaleY) / this.scale;

    const cx = Math.floor(px);
    const cy = Math.floor(py);

    // Miękki pędzel 3x3: środek najmocniej, sąsiedzi słabiej.
    const brush = [
      [0.4, 0.7, 0.4],
      [0.7, 1.0, 0.7],
      [0.4, 0.7, 0.4],
    ];

    for (let dy = -1; dy <= 1; dy++) {
      for (let dx = -1; dx <= 1; dx++) {
        const x = cx + dx;
        const y = cy + dy;
        if (x < 0 || y < 0 || x >= this.size || y >= this.size) continue;
        const idx = y * this.size + x;
        const strength = brush[dy + 1][dx + 1];
        if (this.erasing) {
          this.pixels[idx] = Math.max(0, this.pixels[idx] - strength);
        } else {
          this.pixels[idx] = Math.min(1, this.pixels[idx] + strength);
        }
      }
    }
    this.render();
  }

  /** Czyści cały obrazek. */
  clear() {
    this.pixels.fill(0);
    this.render();
  }

  /** Czy narysowano cokolwiek? (do walidacji) */
  isEmpty() {
    return this.pixels.every((v) => v === 0);
  }

  /** Zwraca kopię pikseli (1024 wartości 0..1). */
  getPixels() {
    return this.pixels.slice();
  }

  /** Rysuje aktualny stan obrazka na canvasie. */
  render() {
    const { ctx, scale, size } = this;

    // Tło.
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);

    // Piksele (im większa wartość, tym ciemniejszy).
    for (let y = 0; y < size; y++) {
      for (let x = 0; x < size; x++) {
        const v = this.pixels[y * size + x];
        if (v > 0) {
          const shade = Math.round(255 * (1 - v));
          ctx.fillStyle = `rgb(${shade},${shade},${shade})`;
          ctx.fillRect(x * scale, y * scale, scale, scale);
        }
      }
    }

    // Delikatna siatka pomocnicza.
    ctx.strokeStyle = 'rgba(0,0,0,0.06)';
    ctx.lineWidth = 1;
    for (let i = 0; i <= size; i++) {
      ctx.beginPath();
      ctx.moveTo(i * scale, 0);
      ctx.lineTo(i * scale, this.canvas.height);
      ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(0, i * scale);
      ctx.lineTo(this.canvas.width, i * scale);
      ctx.stroke();
    }
  }
}

window.PixelEditor = PixelEditor;

