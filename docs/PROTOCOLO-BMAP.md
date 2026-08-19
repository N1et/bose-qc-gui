# Comunicação com o Bose QuietComfort Ultra

Este documento é o contrato de implementação usado pelo app gráfico. Ele foi
extraído de `bose-cli/src/bmap.rs`, `bose-cli/src/macos_rfcomm.m` e das provas de
hardware registradas em `bose-cli/PROTOCOL.md`.

## Arquitetura

O scan BLE serve apenas para descoberta. Configuração usa **BMAP sobre Bluetooth
Classic RFCOMM/SPP**. No macOS, `CoreBluetooth` não abre RFCOMM; o app usa
`IOBluetooth` por uma ponte Objective-C.

Em versões recentes do macOS, `openRFCOMMChannelSync` pode retornar
`kIOReturnError` imediatamente e o `bluetoothd` concluir a conexão dezenas de
milissegundos depois. Por isso, a ponte usa `openRFCOMMChannelAsync` e aguarda
até 8 segundos pelo callback `rfcommChannelOpenComplete:status:`.

Os modelos reconhecidos usam os canais abaixo, já validados em hardware. A
consulta SDP permanece disponível para investigação de modelos futuros, mas não
substitui esses valores: no QC Ultra 2 há registros que também contêm o UUID
Bose e apontam para o canal 14, que recusa tráfego BMAP.

| Modelo | Nome observado | Canal RFCOMM |
|---|---|---:|
| QuietComfort Ultra Headphones 2 | `Bose QC Ultra 2 HP` | 2 |
| QuietComfort 45 | `Bose QuietComfort 45` | 9 |

UUID BMAP conhecido: `00000000-deca-fade-deca-deafdecacaff`.

## Quadro BMAP

Cada quadro é `fblock, function, flags, payload_length, payload...`. O operador
fica no nibble baixo de `flags`, portanto a leitura sempre usa `flags & 0x0f`.
O payload tem no máximo 255 bytes.

| Op | Nome | Uso |
|---:|---|---|
| 1 | GET | leitura |
| 2 | SETGET | escrita com retorno |
| 3 | STATUS | estado retornado |
| 4 | ERROR | erro; primeiro byte é o código |
| 5 | START | dispara ação |
| 6 | RESULT | resultado |
| 7 | PROCESSING | ação assíncrona iniciada |

Escritas `SET` puras costumam exigir autenticação Bose/cloud. O app limita-se a
`GET`, `START` e `SETGET`, já verificados sem autenticação.

## Comandos implementados

### Modo — `[31.3] START`

Payload `[mode_index, voice_prompt]`, com `voice_prompt = 0`. No Ultra 2:
Silêncio=0, Atento=1, Imersão=2, Cinema=3. O retorno aceito é STATUS ou RESULT.

Exemplo Silêncio: `1f 03 05 02 00 00`.

### Ruído e áudio imersivo — `[31.10] SETGET`

Payload `[cnc, auto_cnc, spatial, wind, anc]`:

- `cnc = 10 - nivel_da_interface`; BMAP 0 é ANC máximo e 10 é ambiente máximo;
- `auto_cnc = 0` e `wind = 0`;
- `spatial`: desligado=0, parado=1, movimento=2;
- `anc`: desligado=0, ligado=1.

O QC45 não suporta este endereço; nele ruído é controlado apenas pelos modos.

### Reconciliation between modes and manual controls

The UI treats each built-in mode as a complete preset. Selecting a mode updates
Noise Control and Immersive Audio to the matching values before transmission.
Changing either control manually clears the selected preset and displays
`MANUAL`; in this state the app does not send `[31.3] START`, so the live
`[31.10] SETGET` values cannot overwrite a mode command from the same batch.

Changes are synchronized automatically. Discrete controls use a short 150 ms
delay; continuous Noise Control and EQ sliders use a 550 ms debounce so dragging
does not flood the RFCOMM session. If a change occurs during an active sync, the
latest settings are queued and sent after the current batch completes.

The main window and menu bar panel share one `AppModel` and therefore one
persistent RFCOMM session. Quick controls in the menu bar use the same preset
reconciliation and automatic synchronization path as the full interface.

### Equalizador — `[1.7] SETGET`

Um quadro por banda com payload `[value, band_id]`: graves=0, médios=1,
agudos=2. `value` é inteiro assinado de -10 a +10 codificado em complemento de
dois (`-10 = 0xf6`).

### Bateria — `[2.2] GET`

Payload vazio. O primeiro byte do STATUS/RESULT é a porcentagem.

## Ordem, tempo e validação

O app abre **uma única sessão RFCOMM persistente**, envia modo, espera 750 ms,
envia ruído/imersão, espera 250 ms e envia as três bandas de EQ com 250 ms entre
elas. Reutilizar a sessão é necessário: abrir e fechar um canal para cada quadro
pode deixar o stack Bluetooth do macOS ocupado e fazer a segunda aplicação
falhar com `kIOReturnError` (`0xe00002bc`). Cada resposta pode chegar fragmentada
ou conter vários quadros; a ponte acumula bytes até formar quadros completos.

Todas as transações são serializadas. A sessão continua aberta e é reutilizada
pelos próximos cliques em Aplicar e pelas leituras de bateria. Ela só é descartada
quando ocorre erro, o dispositivo muda ou o processo termina; depois de um
fechamento há uma janela de 650 ms antes de permitir nova abertura do canal.

A camada Swift rejeita resposta parcial, endereço `[fblock.function]` diferente,
operador inesperado e ERROR. O timeout por transação é 8 segundos.

O estado `isConnected` do `IOBluetooth` é mostrado apenas como informação, pois
pode ficar desatualizado. Depois que um fone é selecionado, o botão Aplicar fica
disponível. Se o API indicar que não existe conexão baseband, o app tenta
acordá-la com `IOBluetoothDevice.openConnection()` antes de abrir RFCOMM. Essa
tentativa é best-effort: versões recentes do macOS podem informar
`isConnected=false` enquanto o áudio A2DP está tocando e retornar um erro de
“conexão existente”. Por isso, o app sempre tenta RFCOMM em seguida e não usa
esse booleano para decidir se o fone está realmente conectado.

## Limites atuais

- O foco e caminho testado é QC Ultra 2; há compatibilidade básica com QC45.
- O app lê bateria, mas ainda não reconcilia modo, ANC, imersão e EQ do hardware.
- Modos customizados, multiponto, renomear, sidetone, auto-pause e energia não
  foram implementados porque os caminhos conhecidos exigem mais validação ou
  autenticação.

Nota de auditoria: o código antigo do CLI mapeia `Aware` do QC45 para 1, mas as
notas de prova de hardware do mesmo repositório registram índice 2. Este projeto
usa 2, que é o valor documentado como verificado.
