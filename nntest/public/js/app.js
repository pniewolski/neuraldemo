/**
 * app.js
 * ==================================================================
 * GŁÓWNA LOGIKA APLIKACJI – spina ze sobą wszystkie elementy:
 *   - przełączanie ekranów (menu / generowanie / uczenie / rozpoznawanie),
 *   - edytor obrazków (PixelEditor),
 *   - sieć neuronową (NeuralNetwork) i jej wizualizację (Visualizer),
 *   - komunikację z backendem (api).
 *
 * Nauczona sieć żyje w pamięci przeglądarki (window.trainedNetwork),
 * dzięki czemu po nauce możemy od razu przejść do rozpoznawania.
 * ==================================================================
 */

// Sieć nauczona w bieżącej sesji (albo null, jeśli jeszcze nie uczono).
window.trainedNetwork = null;

// Uchwyty do edytorów (tworzymy je raz, przy pierwszym wejściu na ekran).
let generateEditor = null;
let recognizeEditor = null;

// Wizualizatory dla ekranu uczenia i rozpoznawania.
let trainViz = null;
let recognizeViz = null;

// Flaga zatrzymania uczenia.
let trainingStop = false;

/* ---------------------------------------------------------------- */
/* Narzędzia pomocnicze                                              */
/* ---------------------------------------------------------------- */

const $ = (id) => document.getElementById(id);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** Pokazuje wybrany ekran, chowając pozostałe. */
function showScreen(id) {
  document.querySelectorAll('.screen').forEach((s) => s.classList.remove('active'));
  $(id).classList.add('active');
}

/** Buduje listę unikalnych etykiet z próbek. */
function uniqueLabels(samples) {
  return [...new Set(samples.map((s) => s.label))].sort();
}

/* ---------------------------------------------------------------- */
/* EKRAN GŁÓWNY                                                      */
/* ---------------------------------------------------------------- */

async function refreshHomeStats() {
  const stats = await api.getStats();
  const box = $('home-stats');
  if (!stats.length) {
    box.innerHTML = '<em>Brak danych treningowych. Zacznij od "Generuj dane treningowe".</em>';
    return;
  }
  const total = stats.reduce((s, x) => s + x.count, 0);
  const rows = stats
    .map((s) => `<li><b>${s.label}</b>: ${s.count} obrazków</li>`)
    .join('');
  box.innerHTML =
    `<p>Zebrane dane (${total} obrazków, ${stats.length} etykiet):</p><ul>${rows}</ul>`;
}

/* ---------------------------------------------------------------- */
/* EKRAN: GENEROWANIE DANYCH TRENINGOWYCH                            */
/* ---------------------------------------------------------------- */

function initGenerateScreen() {
  if (!generateEditor) {
    generateEditor = new PixelEditor($('editor-generate'));
  }
  $('generate-status').textContent = '';
}

async function saveTrainingSample() {
  const label = $('label-input').value.trim();
  if (!label) {
    $('generate-status').textContent = 'Wpisz najpierw etykietę (co to jest).';
    return;
  }
  if (generateEditor.isEmpty()) {
    $('generate-status').textContent = 'Najpierw narysuj obrazek.';
    return;
  }

  await api.saveSample(label, generateEditor.getPixels());

  // Po zapisaniu czyścimy RYSUNEK, ale zostawiamy etykietę –
  // dzięki temu wygodnie narysujemy wiele obrazków tego samego znaku.
  generateEditor.clear();
  $('generate-status').textContent =
    `Zapisano obrazek dla "${label}". Narysuj kolejny lub zmień etykietę.`;
  $('label-input').focus();
}

/* ---------------------------------------------------------------- */
/* EKRAN: UCZENIE                                                    */
/* ---------------------------------------------------------------- */

async function initTrainScreen() {
  if (!trainViz) trainViz = new Visualizer($('viz-train'));
  $('train-status').textContent = 'Kliknij "Rozpocznij uczenie".';
  $('btn-start-training').disabled = false;
  $('btn-stop-training').disabled = true;
}

async function startTraining() {
  const samples = await api.getSamples();
  if (samples.length < 2) {
    $('train-status').textContent =
      'Potrzebujesz przynajmniej kilku obrazków (najlepiej po kilka na każdy znak).';
    return;
  }

  const labels = uniqueLabels(samples);

  // Przygotowujemy zbiór uczący: obrazek 32x32 -> wejście 8x8 (64 wartości).
  const dataset = samples.map((s) => ({
    input: downsample(s.pixels),
    label: s.label,
  }));

  // Tworzymy świeżą sieć i podpinamy ją do wizualizatora.
  const net = new NeuralNetwork(labels, 0.5);
  trainViz.setNetwork(net);
  trainViz.draw({ mode: 'weights' }); // na start pokazujemy losowe wagi

  trainingStop = false;
  $('btn-start-training').disabled = true;
  $('btn-stop-training').disabled = false;

  const MAX_EPOCHS = 800; // górny limit
  const EPOCHS_PER_FRAME = 6; // ile epok liczymy między odświeżeniami
  let epoch = 0;
  let loss = 1;

  // Pętla uczenia. Liczymy PACZKAMI epok, a między nimi oddajemy
  // sterowanie przeglądarce (setTimeout 0) – dzięki temu UI się nie
  // zawiesza i widać animację, ale samo uczenie NIE jest spowalniane.
  while (epoch < MAX_EPOCHS && loss > 0.005 && !trainingStop) {
    for (let k = 0; k < EPOCHS_PER_FRAME && epoch < MAX_EPOCHS; k++) {
      loss = net.trainEpoch(dataset);
      epoch++;
    }

    // Do wizualizacji przepuszczamy losową próbkę – widać wtedy,
    // jak sygnał płynie przez sieć przy AKTUALNYCH wagach.
    const demo = dataset[Math.floor(Math.random() * dataset.length)];
    net.forward(demo.input);
    trainViz.draw({ mode: 'signal' });

    $('train-status').innerHTML =
      `Epoka: <b>${epoch}</b> &nbsp;|&nbsp; błąd (koszt): <b>${loss.toFixed(4)}</b>` +
      ` &nbsp;|&nbsp; etykiety: ${labels.join(', ')}`;

    await sleep(0); // oddajemy sterowanie – bez sztucznego spowalniania
  }

  // Zapisujemy nauczoną sieć do użycia w rozpoznawaniu.
  window.trainedNetwork = net;
  $('btn-start-training').disabled = false;
  $('btn-stop-training').disabled = true;
  $('train-status').innerHTML +=
    trainingStop ? ' — przerwano.' : ' — <b>gotowe!</b> Możesz przejść do rozpoznawania.';
}

/* ---------------------------------------------------------------- */
/* EKRAN: ROZPOZNAWANIE                                              */
/* ---------------------------------------------------------------- */

function initRecognizeScreen() {
  if (!recognizeEditor) recognizeEditor = new PixelEditor($('editor-recognize'));
  if (!recognizeViz) recognizeViz = new Visualizer($('viz-recognize'));

  if (!window.trainedNetwork) {
    $('recognize-result').textContent =
      'Sieć nie jest jeszcze nauczona. Wróć i użyj przycisku "Uczenie".';
    return;
  }

  // Przed rozpoznawaniem pokazujemy WAGI jako kolory połączeń.
  recognizeViz.setNetwork(window.trainedNetwork);
  recognizeViz.draw({ mode: 'weights' });
  $('recognize-result').textContent = 'Narysuj znak i kliknij "Rozpoznaj".';
}

async function recognizeDrawing() {
  const net = window.trainedNetwork;
  if (!net) return;
  if (recognizeEditor.isEmpty()) {
    $('recognize-result').textContent = 'Najpierw narysuj znak.';
    return;
  }

  // Zmniejszamy obrazek do wejścia sieci i wykonujemy krok w przód.
  const input = downsample(recognizeEditor.getPixels());
  const result = net.predict(input); // to również wypełnia net.activations

  // ANIMACJA "krok po kroku": sygnał zapala kolejne warstwy.
  // Tę animację lekko spowalniamy, aby dobrze pokazać proces.
  $('recognize-result').textContent = 'Sieć myśli...';
  const numLayers = net.layers.length + 1; // wejście + warstwy
  for (let reveal = 0; reveal < numLayers; reveal++) {
    recognizeViz.draw({ mode: 'signal', reveal });
    await sleep(650); // celowe, umiarkowane spowolnienie animacji
  }
  recognizeViz.draw({ mode: 'signal', reveal: numLayers });

  $('recognize-result').innerHTML =
    `Rozpoznano: <b style="font-size:1.3em">${result.label}</b>` +
    ` &nbsp;(pewność ${(result.confidence * 100).toFixed(0)}%)`;
}

/* ---------------------------------------------------------------- */
/* Podłączenie przycisków po załadowaniu strony                      */
/* ---------------------------------------------------------------- */

window.addEventListener('DOMContentLoaded', () => {
  // Menu główne.
  $('btn-generate').addEventListener('click', () => {
    showScreen('screen-generate');
    initGenerateScreen();
  });
  $('btn-train').addEventListener('click', () => {
    showScreen('screen-train');
    initTrainScreen();
  });
  $('btn-recognize').addEventListener('click', () => {
    showScreen('screen-recognize');
    initRecognizeScreen();
  });

  // Powroty do menu.
  document.querySelectorAll('.btn-home').forEach((b) =>
    b.addEventListener('click', () => {
      showScreen('screen-home');
      refreshHomeStats();
    })
  );

  // Ekran generowania.
  $('btn-save-sample').addEventListener('click', saveTrainingSample);
  $('btn-clear-editor').addEventListener('click', () => generateEditor.clear());

  // Ekran uczenia.
  $('btn-start-training').addEventListener('click', startTraining);
  $('btn-stop-training').addEventListener('click', () => {
    trainingStop = true;
  });

  // Ekran rozpoznawania.
  $('btn-recognize-run').addEventListener('click', recognizeDrawing);
  $('btn-clear-recognize').addEventListener('click', () => {
    recognizeEditor.clear();
    if (window.trainedNetwork) recognizeViz.draw({ mode: 'weights' });
  });

  // Start: pokaż menu i statystyki.
  refreshHomeStats();
});


