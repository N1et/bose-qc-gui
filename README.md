# Bose Control para macOS

Aplicativo nativo em SwiftUI para controlar Bose QuietComfort Ultra Headphones
2 pelo Bluetooth clássico do macOS. O app permite escolher um fone pareado,
trocar modo, ajustar cancelamento de ruído, áudio imersivo e equalizador, além de
ler a bateria.

O ícone de headphones na menu bar oferece acesso rápido a modos, Noise Control
e Immersive Audio. A janela principal continua disponível para EQ e controles
completos.

## Gerar o `.dmg`

Requisitos: macOS 13 ou mais recente e Xcode/Command Line Tools.

```sh
chmod +x scripts/build-dmg.sh
./scripts/build-dmg.sh
```

O artefato será criado em `build/BoseControl-0.5.0-beta.1.dmg`. A assinatura gerada é
ad-hoc para uso local. Para distribuir publicamente, use um certificado Apple
Developer ID e notarização.

O fone deve estar pareado no Ajustes do Sistema e, para aplicar configurações,
conectado ao Mac. A primeira abertura solicita acesso ao Bluetooth.

## Desenvolvimento

```sh
swift test
swift run BoseControl
```

A especificação da comunicação está em
[`docs/PROTOCOLO-BMAP.md`](docs/PROTOCOLO-BMAP.md). O projeto antigo permanece em
`bose-cli/` apenas como referência.
