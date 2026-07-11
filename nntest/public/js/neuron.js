/**
 * neuron.js
 * ==================================================================
 * KLASA NEURON – serce sieci neuronowej.
 *
 * Ta klasa jest napisana z myślą o CZYTELNOŚCI i WARTOŚCI EDUKACYJNEJ,
 * a nie o wydajności. Każdy krok jest rozpisany "na piechotę", żeby
 * było widać dokładnie, co się dzieje.
 *
 * Czym jest neuron?
 * -----------------
 * Neuron to bardzo prosty "kalkulator". Dostaje na wejściu kilka liczb
 * (sygnały od neuronów z poprzedniej warstwy) i zwraca jedną liczbę.
 *
 * Działa w trzech krokach:
 *   1. Każdy sygnał wejściowy mnoży przez odpowiadającą mu WAGĘ.
 *      (waga = jak bardzo ten neuron "słucha" danego wejścia)
 *   2. Sumuje wszystkie te iloczyny i dodaje BIAS (przesunięcie).
 *   3. Wynik przepuszcza przez FUNKCJĘ AKTYWACJI, która "spłaszcza"
 *      dowolną liczbę do zakresu 0..1 (używamy sigmoidy).
 *
 * Uczenie sieci polega na stopniowym dobieraniu wag i biasów tak,
 * aby sieć dawała poprawne odpowiedzi.
 * ==================================================================
 */

/**
 * Funkcja aktywacji – SIGMOIDA.
 * Przekształca dowolną liczbę rzeczywistą na wartość z przedziału (0, 1).
 * Dzięki temu wyjście neuronu można interpretować jak "pobudzenie":
 *   ~0 = neuron milczy, ~1 = neuron mocno pobudzony.
 */
function sigmoid(x) {
  return 1 / (1 + Math.exp(-x));
}

/**
 * Pochodna sigmoidy – potrzebna przy uczeniu (propagacja wsteczna).
 * Ciekawostka: da się ją wyrazić przez samą wartość wyjścia:
 *   sigmoid'(x) = sigmoid(x) * (1 - sigmoid(x))
 */
function sigmoidDerivative(output) {
  return output * (1 - output);
}

/** Mała losowa liczba na start – żeby neurony nie były identyczne. */
function randomWeight() {
  return Math.random() * 2 - 1; // zakres -1 .. 1
}

class Neuron {
  /**
   * @param {number} numInputs – ile sygnałów wejściowych dostaje neuron
   *        (czyli ile neuronów jest w poprzedniej warstwie).
   */
  constructor(numInputs) {
    // Jedna waga na każde wejście.
    //
    // WAŻNE dla skuteczności uczenia: losujemy małe wagi skalowane
    // przez 1/sqrt(liczba_wejść). To tzw. inicjalizacja Xaviera.
    // Gdyby wagi były zbyt duże, suma ważona byłaby ogromna, a sigmoida
    // "nasycałaby się" (dawała prawie 0 lub prawie 1), przez co jej
    // pochodna byłaby bliska zeru i sieć praktycznie przestałaby się uczyć.
    const scale = 1 / Math.sqrt(numInputs);
    this.weights = [];
    for (let i = 0; i < numInputs; i++) {
      this.weights.push(randomWeight() * scale);
    }

    // Bias zaczynamy od zera – neuron sam dobierze sobie próg podczas nauki.
    this.bias = 0;

    // Wartości pomocnicze zapamiętywane w trakcie działania –
    // przydają się przy uczeniu ORAZ przy wizualizacji.
    this.inputs = []; // ostatnie sygnały wejściowe
    this.sum = 0; // suma ważona + bias (przed aktywacją)
    this.output = 0; // wyjście po funkcji aktywacji (0..1)
    this.delta = 0; // "błąd" neuronu wyliczany podczas uczenia
  }

  /**
   * KROK W PRZÓD (forward pass) dla pojedynczego neuronu.
   * Oblicza wyjście na podstawie podanych sygnałów wejściowych.
   *
   * @param {number[]} inputs – sygnały z poprzedniej warstwy
   * @returns {number} wyjście neuronu (0..1)
   */
  activate(inputs) {
    this.inputs = inputs;

    // 1 + 2. Suma ważona: (waga_i * wejście_i) dla wszystkich i, plus bias.
    let sum = this.bias;
    for (let i = 0; i < this.weights.length; i++) {
      sum += this.weights[i] * inputs[i];
    }
    this.sum = sum;

    // 3. Funkcja aktywacji.
    this.output = sigmoid(sum);
    return this.output;
  }
}

// Udostępniamy klasę i funkcje pomocnicze globalnie (klasyczne <script>).
window.Neuron = Neuron;
window.nnMath = { sigmoid, sigmoidDerivative };


