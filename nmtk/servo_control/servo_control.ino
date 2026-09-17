#include <Servo.h>

Servo myServo;

const int SERVO_PIN = 2;  // Change to your pin
int angle = 90;            // Start at center

void setup() {
  Serial.begin(115200);
  myServo.attach(SERVO_PIN);
  myServo.write(angle);

  Serial.println("=== Servo Angle Control ===");
  Serial.println("Commands via Serial Monitor:");
  Serial.println("  w / s  -> +1 / -1 degree");
  Serial.println("  e / d  -> +10 / -10 degrees");
  Serial.println("  0-180  -> jump to angle (type number + Enter)");
  Serial.println("===========================");
  printAngle();
}

void loop() {
  if (Serial.available()) {
    String input = Serial.readStringUntil('\n');
    input.trim();

    if (input.length() == 1) {
      char cmd = input.charAt(0);
      switch (cmd) {
        case 'w': angle += 1;  break;
        case 's': angle -= 1;  break;
        case 'e': angle += 10; break;
        case 'd': angle -= 10; break;
        default:
          Serial.println("Unknown command. Use w/s (+/-1) or e/d (+/-10)");
          return;
      }
    } else {
      int val = input.toInt();
      if (val == 0 && input != "0") {
        Serial.println("Invalid input.");
        return;
      }
      angle = val;
    }

    angle = constrain(angle, 0, 180);
    myServo.write(angle);
    printAngle();
  }
}

void printAngle() {
  Serial.print("Angle: ");
  Serial.print(angle);
  Serial.println(" deg");
}
