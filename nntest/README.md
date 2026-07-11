# 🧠 Sieć neuronowa – aplikacja edukacyjna

Aplikacja pokazująca **zasadę działania sieci neuronowej** na przykładzie
rozpoznawania rysowanych ręcznie znaków 32×32 piksele. Nacisk położono na
**czytelność kodu i wartość dydaktyczną**, a nie na wydajność.

## Co potrafi

- **Generuj dane treningowe** – prosty edytor 32×32, w którym rysujesz znak,
  wpisujesz jego etykietę i zapisujesz (na serwerze). Dla każdego znaku rysujesz
  wiele obrazków; po zapisaniu rysunek się czyści.
- **Uczenie** – sieć uczy się na zebranych danych. Animacja na `canvas` pokazuje
  neurony (kółka w warstwach) i połączenia (linie), a kolory linii kodują
  przekazywane wartości. Uczenie działa szybko (nie jest sztucznie spowalniane).
- **Rozpoznawanie** – rysujesz znak, a sieć go rozpoznaje. Najpierw kolory linii
  pokazują **wagi**, a po kliknięciu „Rozpoznaj” – **sygnał** płynący przez sieć
  (animacja lekko spowolniona, by lepiej pokazać proces).

## Uruchomienie

```powershell
npm install
npm start
```

Następnie otwórz w przeglądarce: <http://localhost:3000>

## Budowa sieci

`WEJŚCIE (8×8 = 64) → WARSTWA UKRYTA (16) → WYJŚCIE (po jednym neuronie na etykietę)`

Obrazek 32×32 jest zmniejszany (uśrednianie bloków 4×4) do siatki 8×8 –
to świadome **uproszczenie edukacyjne**, dzięki któremu sieć i jej wizualizacja
pozostają czytelne. Funkcja aktywacji: sigmoida. Uczenie: propagacja wsteczna
(backpropagation) z prostym spadkiem gradientu.

## Przechowywanie danych

Backend (Node.js + Express) zapisuje próbki w **SQLite** (`better-sqlite3`).
Jeśli natywny moduł SQLite nie da się skompilować (np. starsza wersja Node lub
brak narzędzi build), aplikacja **automatycznie** przełącza się na lekki magazyn
w pliku JSON (`data/samples.json`) – działa wtedy identycznie.

> Uwaga: `better-sqlite3` w nowszych wersjach wymaga Node ≥ 18. Na starszym Node
> zadziała magazyn JSON (fallback) – funkcjonalnie bez różnicy.

## Struktura projektu

```
server.js              – backend (tylko zapis/odczyt danych)
db.js                  – magazyn: SQLite z fallbackiem do JSON
public/
  index.html           – interfejs (3 ekrany)
  css/style.css        – style
  js/
    neuron.js          – klasa Neuron (rdzeń edukacyjny)
    network.js         – klasa NeuralNetwork (forward + backprop)
    editor.js          – edytor pikselowy 32×32
    visualizer.js      – wizualizacja sieci na canvas
    api.js             – komunikacja z backendem
    app.js             – logika ekranów i spięcie całości
```

## Wskazówka dydaktyczna

Najlepiej zacząć od dwóch–trzech różnych znaków (np. „A”, „B”, „O”), rysując po
kilka–kilkanaście obrazków każdego. Im więcej i im bardziej zróżnicowane dane,
tym lepiej sieć się nauczy.

