# Porto Lume — Protótipo 02 · Godot 2D

Protótipo original de exploração urbana top-down para smartphones. Feito em **Godot 4.6.3, GDScript e renderer Compatibility (WebGL 2)**. Gráficos são placeholders geométricos desenhados no Godot, sem dependências de arte ou plugins.

## O que está funcionando

- Pequeno bairro de 2400 × 1800 unidades: ruas, faixas de pedestres, calçadas, pátios e 18 construções com colisão.
- Personagem com oito direções, velocidade diagonal normalizada e câmera com acompanhamento suave.
- Joystick touchscreen fixo no canto inferior esquerdo, com deadzone e captura de um dedo. Soltar/cancelar o toque, mudar a orientação ou perder o foco libera o controle.
- Carro coral original controlável, com aceleração, freio/ré, direção arcade, desaceleração progressiva e colisão com construções, limites e obstáculos.
- Segundo carro estacionado com colisão, sem interação nesta versão.
- Botão contextual **ENTRAR/SAIR**, pedais touchscreen independentes e câmera suave que acompanha o jogador ou o carro.
- Saída do veículo em uma posição livre próxima; se não houver espaço seguro, o jogador permanece dentro.
- Interface adaptável ao tamanho da tela e prioridade landscape. Controles liberam os toques ao perder foco ou mudar a orientação.
- Teclado WASD/setas e **E** para entrar/sair; também é possível arrastar o joystick e pressionar os botões com o mouse.

O personagem tem uma jaqueta coral e começa na rua ao sul do cruzamento central. O mapa, os nomes e os elementos visuais são originais. Não foram adicionados armas, polícia, NPCs, trânsito, dano, missões, dinheiro ou wanted.

## Como dirigir

1. Caminhe até o carro coral. O botão **ENTRAR** aparece à direita quando o personagem está perto e consegue alcançar o veículo.
2. Toque em **ENTRAR**. O personagem fica oculto, a mesma câmera passa a seguir o carro e aparecem os pedais.
3. Mantenha **ACELERAR** pressionado e mova o joystick para a esquerda ou direita para virar. O eixo vertical do joystick não acelera o veículo.
4. Use **FREAR / RÉ** para parar. Mantenha o pedal pressionado após parar para recuar; a direção acompanha o sentido da marcha. Se os dois pedais estiverem pressionados, o freio tem prioridade.
5. Solte os pedais para desacelerar gradualmente. Arrastar o dedo para fora de um pedal também o libera; é preciso um novo toque para pressioná-lo novamente.
6. Toque em **SAIR** para estacionar e procurar uma posição segura ao lado do carro. Sem espaço livre, a mensagem **Sem espaço para sair** aparece e o jogador permanece dentro.

No teclado, **W/↑** acelera, **S/↓** freia e recua, **A/D** ou **←/→** viram e **E** entra/sai. A pé, WASD/setas continuam movendo o personagem nas oito direções.

## Abrir no Godot

1. Instale o **Godot 4.6.3 Standard**, sem necessidade de .NET.
2. Importe `project.godot` no gerenciador de projetos.
3. Pressione **F6** para executar uma cena aberta ou **F5** para o jogo completo.

Use o renderer **Compatibility**. O renderer chamado “Mobile” no Godot não é o renderer desta versão Web.

## Jogar no Safari pelo GitHub Pages

O MVP já está publicado em **[https://henrique-purri.github.io/porto-lume/](https://henrique-purri.github.io/porto-lume/)** e foi validado pelo usuário no Safari do iPhone. Não é necessário computador, localhost ou Wi-Fi local. O fluxo completo está em [docs/GITHUB_PAGES.md](docs/GITHUB_PAGES.md).

O workflow `.github/workflows/deploy-pages.yml` constrói o jogo com **Godot 4.6.3 e templates da mesma versão** em ambiente preparado, verifica os arquivos exportados e publica no Pages a cada atualização da branch `main`. Também pode ser iniciado manualmente pela aba Actions. O Pages precisa usar **GitHub Actions** como origem em **Settings → Pages**.

Abra o endereço acima no Safari do iPhone, gire o aparelho para landscape e toque em **Iniciar exploração**. Desative o bloqueio de rotação se necessário. A atualização de veículos ficará disponível nesse mesmo endereço depois que os jobs de build e publicação do respectivo commit estiverem verdes.

O repositório do projeto é [henrique-purri/porto-lume](https://github.com/henrique-purri/porto-lume), na branch `main`. Não abra o HTML pelo app Arquivos: o Godot precisa servir também JavaScript, WebAssembly e o pacote do jogo por HTTP/HTTPS.

O [GitHub Actions](https://github.com/henrique-purri/porto-lume/actions) confere Godot e templates **4.6.3**, executa os dois testes integrados e verifica HTML, JS, WASM e PCK. O artefato `github-pages` contém o build completo. O Pages já está configurado; cada push em `main` inicia uma nova publicação. O resultado de cada atualização aparece nos jobs **Godot 4.6.3 · Web single-thread** e **Publicar jogo**.

A exportação usa caminhos relativos, funciona em subpastas do Pages e não requer backend ou cabeçalhos de isolamento de origem. O servidor `tools/serve_web.py` fica disponível apenas para desenvolvimento; ele não faz parte do acesso pelo iPhone.

### Safari e desempenho

- Use Safari/iOS atualizado com **WebGL 2 e WebAssembly** habilitados. A compatibilidade final depende do aparelho e da versão do sistema.
- Exportação **single-thread**; não requer `SharedArrayBuffer`, COOP/COEP ou service worker.
- A página respeita notch e indicador de início com `safe-area-inset-*`, bloqueia o scroll durante o toque e redimensiona o canvas ao girar.
- Landscape é uma preferência; o Safari pode exigir que você gire o aparelho manualmente. O shell orienta o usuário em portrait.
- Cena simples, sem iluminação dinâmica, navegação, áudio, texturas grandes ou lógica de tráfego. Movimento e física ficam concentrados no jogador ou veículo ativo, na câmera, na interação e nos controles.
- O primeiro carregamento baixa o runtime Web do Godot. Não foi implementado suporte offline.

## Gerar novamente a versão Web

No Godot, abra **Editor → Manage Export Templates** e instale os templates da mesma versão do editor. Depois use **Project → Export → Web → Export Project** e salve em `build/web/index.html`.

Mantenha no preset: **Thread Support desligado**, **Compatibility**, **PWA desligada** e o shell `web/shell.html`. Há um preset versionado em `export_presets.cfg`.

Também é possível exportar por terminal:

```bash
bash tools/export_web.sh
```

O script usa `godot` ou a variável `GODOT_BIN` para localizar o executável. Requer templates Web correspondentes instalados; não baixa dependências automaticamente.

## Estrutura e arquivos

```text
project.godot                Configuração, inputs, resolução e renderer
export_presets.cfg           Preset Web single-thread
scenes/
  main.tscn                  Composição do jogo: mundo + jogador + HUD
scripts/
  main.gd                    Conecta jogador, HUD e sistema de veículos
  city.gd                    Planta do bairro, ruas, decoração e limites
  building.gd                Bloco reutilizável; arte e colisão compartilham tamanho
  player_controller.gd       Movimento, desenho/animação e foco do jogador
  virtual_joystick.gd        Captura e interpretação de toque/mouse
  mobile_hud.gd              Layout, ação contextual e controles de direção
  touch_action_button.gd     Botão de toque com captura independente por dedo
  vehicle_controller.gd      Direção arcade, frenagem, ré e colisão do carro
  vehicle_interaction.gd     Entrada, saída segura e transferência da câmera
  parked_car.gd              Desenho compartilhado pelos carros
world/
  city.tscn                  Cena do bairro e posições dos carros
  building.tscn              Construção StaticBody2D reutilizável
player/
  player.tscn                CharacterBody2D, colisão circular e Camera2D
vehicles/
  driveable_car.tscn         Carro coral controlável, com corpo e colisão
  parked_car.tscn            Carro estacionado com colisão, sem interação
ui/
  mobile_hud.tscn            CanvasLayer da interface
  virtual_joystick.tscn      Controle reutilizável
  touch_action_button.tscn   Base reutilizável para ação e pedais
assets/
  icon.svg                   Ícone original do projeto
web/
  shell.html                 Página de carregamento adaptada ao Safari
tools/
  export_web.sh              Exportação por linha de comando
  serve_web.py               Servidor HTTP local para o build
tests/
  smoke_test.gd              Validação integrada do protótipo
  vehicle_test.gd            Direção, colisão, entrada/saída e multitouch
build/web/                   Saída gerada pela exportação (não versionada)
.github/workflows/
  deploy-pages.yml           Build automático e publicação HTTPS no GitHub Pages
docs/
  GITHUB_PAGES.md             Configuração do Pages e acesso pelo iPhone
```

Arquivos `.uid` ao lado dos scripts são gerados pelo Godot para manter referências estáveis. A pasta `.godot/` é cache local e não precisa ser compartilhada.

O mapa usa `world/building.tscn` instanciado pela planta em `scripts/city.gd`. A colisão de cada construção acompanha seu `footprint`. O jogador aceita qualquer Node com `get_direction() -> Vector2`; o veículo consulta `get_drive_throttle()` e `get_drive_steering()` no HUD. `vehicle_interaction.gd` coordena a troca de controle, mantém a mesma câmera e verifica posições de saída com a física do mundo. Para alterar o tamanho do mundo, ajuste também os limites da câmera em `player/player.tscn` e `world_bounds` no sistema de interação.

## Verificação

Execute os dois testes integrados pelo terminal:

```bash
godot --headless --path . --script res://tests/smoke_test.gd
godot --headless --path . --script res://tests/vehicle_test.gd
```

No iPhone, valide andar nas oito direções, aproximar-se do carro coral e entrar, usar joystick e pedal com dedos diferentes, frear até engatar ré, soltar os pedais e sair. Encoste o carro em prédios, limites e no carro estacionado; tente sair com um lado bloqueado. Gire a tela e alterne apps durante o controle. A câmera deve seguir o corpo ativo sem girar o mapa, e nenhum dedo solto deve deixar um controle pressionado.

O teste automatizado e a exportação podem ser validados em navegador neste ambiente, mas não substituem o teste em um iPhone físico. Não foi medida uma taxa de FPS em hardware iOS.
