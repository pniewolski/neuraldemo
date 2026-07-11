/**
 * network.js
 * ==================================================================
 * KLASA NEURALNETWORK – sieć neuronowa złożona z warstw neuronów.
 *
 * Filozofia: PROSTOTA i CZYTELNOŚĆ ponad wydajność.
 *
 * Budowa sieci (warstwy):
 *   [ WEJŚCIE ]  →  [ WARSTWA UKRYTA ]  →  [ WARSTWA WYJŚCIOWA ]
 *
 *   - Warstwa wejściowa: to po prostu piksele obrazka (liczby 0..1).
 *     Nie ma tam "prawdziwych" neuronów liczących – to same wartości.
 *   - Warstwa ukryta: neurony, które wyłapują proste wzorce.
 *   - Warstwa wyjściowa: po jednym neuronie na każdą rozpoznawaną
 *     etykietę (klasę). Ten, który się najmocniej pobudzi, wygrywa.
 *
 * UPROSZCZENIE EDUKACYJNE (świadome):
 *   Obrazek ma 32x32 = 1024 piksele. Narysowanie 1024 kółek-neuronów
 *   i tysięcy połączeń byłoby nieczytelne. Dlatego obrazek jest najpierw
 *   NORMALIZOWANY (wyśrodkowany i przeskalowany do ramki otaczającej),
 *   a następnie sprowadzany do siatki 12x12 = 144 wartości (patrz funkcja
 *   `downsample`). To wciąż rozpoznawanie obrazu 32x32, ale sieć i jej
 *   wizualizacja pozostają przejrzyste.
 * ==================================================================
 */

// Uwaga: nie tworzymy tu stałej o nazwie `sigmoidDerivative`, aby nie
// kolidować z globalną funkcją o tej samej nazwie z neuron.js
// (skrypty klasyczne współdzielą zasięg globalny). Używamy aliasu.
const dSigmoid = window.nnMath.sigmoidDerivative;

// Rozmiar "znormalizowanego" obrazka, który trafia na wejście sieci.
// 12x12 = 144 wejścia to dobry kompromis: znacznie więcej szczegółów
// niż 8x8, a wizualizacja wciąż pozostaje czytelna.
const INPUT_GRID = 12; // 12x12
const INPUT_SIZE = INPUT_GRID * INPUT_GRID; // 144
const HIDDEN_SIZE = 24; // liczba neuronów w warstwie ukrytej

/**
 * Przetwarza obrazek 32x32 na wejście sieci (INPUT_GRID x INPUT_GRID).
 *
 * KLUCZOWY KROK dla skuteczności: NORMALIZACJA POŁOŻENIA I ROZMIARU.
 * Ludzie rysują ten sam znak w różnych miejscach i różnej wielkości.
 * Bez normalizacji sieć traktowałaby "A" w lewym górnym rogu i "A"
 * na środku jak zupełnie różne obrazy. Dlatego:
 *   1) znajdujemy "ramkę otaczającą" (bounding box) narysowanego znaku,
 *   2) rozciągamy tę ramkę na całą siatkę wejściową,
 *   3) uśredniamy jasność pikseli w każdej komórce siatki.
 * Dzięki temu znak jest zawsze wyśrodkowany i wypełnia kadr.
 *
 * @param {number[]} pixels32 – 1024 wartości 0..1 (obrazek 32x32)
 * @returns {number[]} INPUT_SIZE wartości 0..1
 */
function downsample(pixels32) {
  const SRC = 32;
  const out = new Array(INPUT_SIZE).fill(0);

  // 1. Ramka otaczająca: najmniejszy prostokąt zawierający narysowane piksele.
  let minX = SRC, minY = SRC, maxX = -1, maxY = -1;
  for (let y = 0; y < SRC; y++) {
    for (let x = 0; x < SRC; x++) {
      if (pixels32[y * SRC + x] > 0.05) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX < 0) return out; // pusty obrazek – same zera

  const boxW = maxX - minX + 1;
  const boxH = maxY - minY + 1;

  // 2 + 3. Każdy piksel źródłowy trafia do komórki siatki wyznaczonej
  // przez jego POZYCJĘ WZGLĘDNĄ w ramce (0..1). W komórkach uśredniamy jasność.
  const sum = new Array(INPUT_SIZE).fill(0);
  const cnt = new Array(INPUT_SIZE).fill(0);
  for (let y = minY; y <= maxY; y++) {
    for (let x = minX; x <= maxX; x++) {
      const nx = (x - minX) / boxW; // 0..1 w poziomie
      const ny = (y - minY) / boxH; // 0..1 w pionie
      const gx = Math.min(INPUT_GRID - 1, Math.floor(nx * INPUT_GRID));
      const gy = Math.min(INPUT_GRID - 1, Math.floor(ny * INPUT_GRID));
      const idx = gy * INPUT_GRID + gx;
      sum[idx] += pixels32[y * SRC + x];
      cnt[idx] += 1;
    }
  }
  for (let i = 0; i < INPUT_SIZE; i++) {
    out[i] = cnt[i] > 0 ? sum[i] / cnt[i] : 0;
  }
  return out;
}

class NeuralNetwork {
  /**
   * @param {string[]} labels – lista rozpoznawanych etykiet (klas).
   *        Rozmiar warstwy wyjściowej = liczba etykiet.
   * @param {number} learningRate – szybkość uczenia (jak duże kroki
   *        robimy przy poprawianiu wag).
   */
  constructor(labels, learningRate = 0.5) {
    this.labels = labels.slice();
    this.learningRate = learningRate;

    // Definicja rozmiarów kolejnych warstw.
    // sizes[0] = wejście, potem ukryta, potem wyjście.
    this.sizes = [INPUT_SIZE, HIDDEN_SIZE, labels.length];

    // Budujemy warstwy neuronów.
    // Warstwy wejściowej NIE budujemy z neuronów – to same piksele.
    // layers[0] = warstwa ukryta, layers[1] = warstwa wyjściowa.
    this.layers = [];
    for (let l = 1; l < this.sizes.length; l++) {
      const numInputs = this.sizes[l - 1];
      const layer = [];
      for (let n = 0; n < this.sizes[l]; n++) {
        layer.push(new Neuron(numInputs));
      }
      this.layers.push(layer);
    }

    // Ostatnie aktywacje wszystkich warstw – do wizualizacji.
    // activations[0] = wejście, activations[1] = ukryta, activations[2] = wyjście.
    this.activations = [new Array(INPUT_SIZE).fill(0)];
    for (const layer of this.layers) {
      this.activations.push(new Array(layer.length).fill(0));
    }
  }

  /**
   * PROPAGACJA W PRZÓD – przepuszczenie sygnału przez całą sieć.
   * @param {number[]} input – 64 wartości wejściowe (obrazek 8x8)
   * @returns {number[]} wartości warstwy wyjściowej (po jednej na etykietę)
   */
  forward(input) {
    this.activations[0] = input.slice(); // zapamiętujemy wejście do wizualizacji

    let signal = input;
    for (let l = 0; l < this.layers.length; l++) {
      const layer = this.layers[l];
      const nextSignal = new Array(layer.length);
      for (let n = 0; n < layer.length; n++) {
        nextSignal[n] = layer[n].activate(signal);
      }
      this.activations[l + 1] = nextSignal;
      signal = nextSignal;
    }
    return signal; // sygnał z ostatniej (wyjściowej) warstwy
  }

  /**
   * Zamienia etykietę na wektor oczekiwanego wyjścia (kodowanie 1-z-N).
   * Np. dla etykiet ["A","B","C"] i celu "B" -> [0, 1, 0].
   */
  targetVector(label) {
    return this.labels.map((l) => (l === label ? 1 : 0));
  }

  /**
   * UCZENIE NA JEDNEJ PRÓBCE (jeden obrazek).
   * To jest esencja "uczenia się" sieci – algorytm propagacji wstecznej
   * (backpropagation) w najprostszej możliwej formie.
   *
   * @param {number[]} input – 64 wartości wejściowe
   * @param {string} label – poprawna etykieta
   * @returns {number} błąd (koszt) dla tej próbki – im mniejszy, tym lepiej
   */
  trainSample(input, label) {
    // --- 1. Krok w przód: policz aktualną odpowiedź sieci. ---
    const output = this.forward(input);
    const target = this.targetVector(label);

    // --- 2. Błąd warstwy WYJŚCIOWEJ. ---
    // Dla każdego neuronu wyjściowego liczymy, jak bardzo się pomylił.
    // delta = (wyjście - cel) * pochodna_aktywacji
    const outputLayer = this.layers[this.layers.length - 1];
    let cost = 0;
    for (let n = 0; n < outputLayer.length; n++) {
      const neuron = outputLayer[n];
      const error = neuron.output - target[n];
      cost += error * error; // sumujemy kwadraty błędów (koszt)
      neuron.delta = error * dSigmoid(neuron.output);
    }

    // --- 3. Błąd warstw UKRYTYCH (propagacja wstecz). ---
    // Idziemy od przedostatniej warstwy do pierwszej.
    // Błąd neuronu ukrytego = suma (waga_do_następnego * delta_następnego),
    // pomnożona przez pochodną jego własnej aktywacji.
    for (let l = this.layers.length - 2; l >= 0; l--) {
      const layer = this.layers[l];
      const nextLayer = this.layers[l + 1];
      for (let n = 0; n < layer.length; n++) {
        let errorSum = 0;
        for (let k = 0; k < nextLayer.length; k++) {
          errorSum += nextLayer[k].weights[n] * nextLayer[k].delta;
        }
        layer[n].delta = errorSum * dSigmoid(layer[n].output);
      }
    }

    // --- 4. Aktualizacja wag i biasów. ---
    // Każdą wagę przesuwamy odrobinę w stronę zmniejszającą błąd:
    //   nowa_waga = stara_waga - tempo * delta * wejście
    for (let l = 0; l < this.layers.length; l++) {
      const layer = this.layers[l];
      for (let n = 0; n < layer.length; n++) {
        const neuron = layer[n];
        for (let w = 0; w < neuron.weights.length; w++) {
          neuron.weights[w] -= this.learningRate * neuron.delta * neuron.inputs[w];
        }
        // bias traktujemy jak wagę od stałego wejścia równego 1
        neuron.bias -= this.learningRate * neuron.delta;
      }
    }

    return cost;
  }

  /**
   * Jedna EPOKA uczenia = jeden przebieg przez wszystkie próbki.
   * Próbki tasujemy, aby sieć nie zapamiętywała kolejności.
   *
   * @param {{input:number[], label:string}[]} dataset
   * @returns {number} średni koszt w tej epoce
   */
  trainEpoch(dataset) {
    const order = shuffledIndices(dataset.length);
    let totalCost = 0;
    for (const i of order) {
      totalCost += this.trainSample(dataset[i].input, dataset[i].label);
    }
    return totalCost / dataset.length;
  }

  /**
   * Rozpoznanie obrazka: zwraca najlepszą etykietę i pełny wektor wyjść.
   * @param {number[]} input – 64 wartości wejściowe
   */
  predict(input) {
    const output = this.forward(input);
    let bestIndex = 0;
    for (let i = 1; i < output.length; i++) {
      if (output[i] > output[bestIndex]) bestIndex = i;
    }
    return {
      label: this.labels[bestIndex],
      confidence: output[bestIndex],
      output: output.slice(),
    };
  }
}

/** Zwraca przetasowaną listę indeksów 0..n-1 (algorytm Fishera–Yatesa). */
function shuffledIndices(n) {
  const arr = Array.from({ length: n }, (_, i) => i);
  for (let i = n - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
}

// Udostępniamy globalnie.
window.NeuralNetwork = NeuralNetwork;
window.nnConfig = { INPUT_GRID, INPUT_SIZE, HIDDEN_SIZE };
window.downsample = downsample;







