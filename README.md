# Khazan Analog Menu (The First Berserker: Khazan)

Mod de acessibilidade para **The First Berserker: Khazan** (Unreal Engine 4.27).
Permite navegar os menus de pausa com o **analógico esquerdo**, mantendo a UI
em modo gamepad (sem que o jogo mude para a UI de teclado/mouse).

## O que faz

- O analógico esquerdo é convertido em D-pad **somente quando um menu está
  aberto**. Durante o gameplay o input passa intacto (câmera normal).
- O d-pad gerado é **pulsado** (press/release em loop), o que faz o menu
  "autoscrollar" enquanto o stick é mantido inclinado — parece nativo.
- O modo do menu é detectado automaticamente e também pode ser alternado
  manualmente com **F11**.

## Componentes

```
khazan-mod/
├── xinput-proxy/                 # XINPUT1_3.dll proxy (C++)
│   ├── dllmain.cpp               # forwards XInput + conversão stick->D-pad
│   ├── exports.def               # exports por ordinal (2/3/100)
│   └── build.bat                 # build MSVC x64
├── lt-toggle/                    # LT_Toggle.dll (plugin opcional)
│   ├── dllmain.cpp
│   └── exports.def
├── Mods/
│   ├── KhazanAnalogMenu/
│   │   └── Scripts/main.lua      # UE4SS mod: detecta menu e escreve o flag
│   ├── mods.txt                  # habilita o mod UE4SS
│   └── shared/
└── backup/ue4ss_v3.0.1_release/  # cópia do UE4SS de referência
```

### Como funciona (arquitetura)

1. **`XINPUT1_3.dll` proxy** intercepta `XInputGetState`/`XInputGetStateEx`
   (ordinais 2, 3 e 100). O jogo importa a DLL por ordinal, então o proxy é
   carregado em seu lugar e encaminha para a DLL real do sistema.
2. **`main.lua` (UE4SS)** roda a cada 200ms e lê a propriedade
   `bShowMouseCursor` do **PlayerController de gameplay** (o que possui um pawn
   válido — não o controller de UI, que fica `true` o tempo todo). Com 3
   amostras iguais (~600ms de debounce), escreve o arquivo `menu_open.flag`.
3. **O proxy** lê `menu_open.flag` a cada `XInputGetState`. Se o flag estiver
   `'1'`, converte o analógico esquerdo em D-pad com histerese e **pulso**
   (110ms press / 50ms gap), zerando o stick para não haver dupla rolagem.
4. **`LT_Toggle.dll`** (opcional, plugin) recebe o estado do gamepad via
   `KhazanLT_OnGamepadState` e alterna o estado virtual do LT em edge detect —
   função independente, não afeta o menu.

## Deploy (estrutura no jogo)

Copiar para `BBQ\Binaries\Win64\` do jogo:

```
XINPUT1_3.dll                     # do xinput-proxy (build)
LT_Toggle.dll                     # do lt-toggle (build)
Mods/
├── KhazanAnalogMenu/
│   └── Scripts/main.lua          # do Mods/KhazanAnalogMenu/Scripts/
└── mods.txt                      # KhazanAnalogMenu : 1
```

O UE4SS precisa estar instalado (usa `experimental-latest`; há um backup de
referência em `backup/ue4ss_v3.0.1_release/`).

> O jogo deve estar **fechado** durante o deploy — a DLL é carregada no boot.

## Teclas

| Tecla | Ação |
|-------|------|
| `F11` | Cicla override manual: auto → ON → OFF → auto |
| `F5`  | Dump de todos os controllers/pawns (diagnóstico) |
| `F6`  | Dump das UFunctions de input/pause/menu do PlayerController |
| `F7`  | Dump de instâncias de UserWidget (menus) |
| `F9`  | Teste isolado de `GetInputAnalogStickState` (apenas no gameplay) |

## Detalhes técnicos relevantes

- **`FindBestPC`**: escolhe o controller que tem um **pawn válido** (o de
  gameplay). NÃO usa `IsPlayerControlled()` — o jogo retorna `false` para o
  personagem do jogador, e exigir isso fazia o código escolher o controller de
  UI cujo `bShowMouseCursor` nunca muda. O controller de gameplay flipeia
  `false` (gameplay) ↔ `true` (menu de pausa).
- **Comparação de identidade do PC**: compara por `GetFullName()` (nome único
  do objeto), nunca por referência Lua — `FindAllOf` devolve um wrapper novo a
  cada chamada, e comparar referências resetava o debounce a cada tick.
- **Crash de input UFunctions**: chamar UFunctions de input via Lua UE4SS
  crasha o jogo (ex.: `GetInputAnalogStickState`, `ReadStickTest`). Leituras de
  **propriedades** (`bShowMouseCursor`, `Pawn`) são seguras. Por isso a
  detecção é baseada em propriedade, não em polling de stick.
- **Sinais descartados**: cursor do SO (some no menu), `IsGamePaused` (retorna
  nil — o jogo não usa pause do UE), hooks de `SetGamePaused`/`SetPause` (nunca
  disparam). `bShowMouseCursor` do controller de gameplay foi o sinal
  vencedor.
- **Pulse vs segurar**: menus UE4/UMG respondem a transições key-down/key-up;
  segurar o d-pad gerava 1 passo só. O pulso gera key-downs repetidos →
  autoscroll.

## Ajustes de afinação

No `xinput-proxy/dllmain.cpp` (em `ApplyStickToDPad`):

| Constante | Valor | Efeito |
|-----------|-------|--------|
| `ENGAGE`  | 12000 | deflexão para ativar |
| `RELEASE` | 8000  | deflexão para soltar (histerese) |
| `PRESS_MS`| 110   | duração do press do d-pad |
| `GAP_MS`  | 50    | intervalo entre presses (velocidade do scroll) |

No `main.lua`:

| Constante | Valor | Efeito |
|-----------|-------|--------|
| `MENU_FLAG_PATH` | caminho do flag | deve apontar para a pasta Win64 do jogo |
| debounce | 3 amostras a 200ms | ~600ms antes de alternar o flag |

## Build (Windows)

```bat
cd xinput-proxy
build.bat        :: gera XINPUT1_3.dll
cd ..\lt-toggle
build.bat        :: gera LT_Toggle.dll
```

Toolchain: MSVC x64 (vcvars64), `cl /LD /O2`.
