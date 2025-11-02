# Azure DevOps Agent Images (Custom Fork)

## Flutter-Unterstützung entfernt

Das Container-Image für Flutter wurde entfernt. Flutter wird jetzt ausschließlich per FVM während der Pipeline installiert und genutzt. Das spart Speicherplatz und vermeidet Versionsdrift.

**Empfohlener Pipeline-Schritt:**

```yaml
- script: |
    curl -L https://github.com/fvm/fvm/releases/latest/download/fvm-linux-x64.tar.gz | tar xz -C /usr/local/bin
    fvm --version
    fvm install 3.35.7
    fvm flutter --version
  displayName: Install FVM and Flutter
```

## Verfügbare Images
- dotnet
- java
- android

## Hinweise
- Kein Flutter-Layer mehr im Image.
- FVM und Flutter werden pro Build installiert und können per Cache-Task beschleunigt werden.
- Capability-Erkennung für Flutter entfällt.

Weitere Infos siehe Doku und Pipeline-Beispiele.