// Blink + hello test for PCBCupid GLYPH C6 (ESP32-C6)
// Onboard LED is on GPIO14
#define LED_PIN 14

void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println("Hello from GLYPH C6!");
  pinMode(LED_PIN, OUTPUT);
}

void loop() {
  digitalWrite(LED_PIN, HIGH);
  Serial.println("LED ON");
  delay(500);
  digitalWrite(LED_PIN, LOW);
  Serial.println("LED OFF");
  delay(500);
}
