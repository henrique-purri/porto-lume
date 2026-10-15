# Porto Lume — MVP Godot 2D

Protótipo original de exploração urbana top-down para smartphones. Feito em **Godot 4.6.3, GDScript e renderer Compatibility (WebGL 2)**. Gráficos são placeholders geométricos desenhados no Godot, sem dependências de arte ou plugins.

## O que está funcionando

- Pequeno bairro de 2400 × 1800 unidades: ruas, faixas de pedestres, calçadas, pátios e 18 construções com colisão.
- Personagem com oito direções, velocidade diagonal normalizada e câmera com acompanhamento suave.
- Joystick touchscreen fixo no canto inferior esquerdo, com deadzone e captura de um dedo. Soltar/cancelar o toque, mudar a orientação ou perder o foco libera o controle.
- Dois carros estacionados exclusivamente visuais; não há direção, interação nem colisão com eles.
- Interface adaptável ao tamanho da tela, prioridade landscape e lado direito sem botões de ação.
- Teclado WASD/setas e arrastar o joystick com o mouse para facilitar os testes no computador.

O personagem tem uma jaqueta coral e começa na rua ao sul do cruzamento central. O mapa, os nomes e os elementos visuais são originais. Não foram adicionados armas, polícia, NPCs, trânsito, missões, dinheiro, wanted ou entrada em veículos.

## Abrir no Godot

1. Instale o **Godot 4.6.3 Standard**, sem necessidade de .NET.
2. Importe `project.godot` no gerenciador de projetos.
3. Pressione **F6** para executar uma cena aberta ou **F5** para o jogo completo.

Use o renderer **Compatibility**. O renderer chamado “Mobile” no Godot não é o renderer desta versão Web.

## Jogar no Safari pelo GitHub Pages

O caminho principal é um link público **HTTPS**, gerado pelo GitHub Pages. Não é necessário computador, localhost ou Wi-Fi local. O fluxo completo está em [docs/GITHUB_PAGES.md](docs/GITHUB_PAGES.md).

O workflow `.github/workflows/deploy-pages.yml` constrói o jogo com **Godot 4.6.3 e templates da mesma versão** em ambiente preparado, verifica os arquivos exportados e publica no Pages a cada atualização da branch `main`. Também pode ser iniciado manualmente pela aba Actions. O Pages precisa usar **GitHub Actions** como origem em **Settings → Pages**.

Após a publicação, abra no Safari do iPhone a URL HTTPS exibida pelo job **deploy**. Gire o aparelho para landscape e toque em **Iniciar exploração**. Desative o bloqueio de rotação se necessário. O endereço de um projeto normalmente segue `https://USUARIO.github.io/REPOSITORIO/`; use a URL real do deploy.

Esta pasta, por si só, não cria um repositório remoto nem habilita o Pages. Para publicar a partir do Codex, conecte sua conta GitHub e informe o repositório de destino. Não abra o HTML pelo app Arquivos: o Godot precisa servir também JavaScript, WebAssembly e o pacote do jogo por HTTP/HTTPS.

**Estado desta entrega:** o código do jogo passou nos testes do Godot, mas o build Web não foi concluído neste ambiente. O proxy recusou o download parcial dos templates e o download completo atingiu o limite de 120 segundos. O workflow usa uma imagem com Godot e templates 4.6.3 já instalados para fazer a exportação no GitHub. Ainda não foi executado nem publicado, porque não há repositório conectado.

A exportação usa caminhos relativos, funciona em subpastas do Pages e não requer backend ou cabeçalhos de isolamento de origem. O servidor `tools/serve_web.py` fica disponível apenas para desenvolvimento; ele não faz parte do acesso pelo iPhone.

### Safari e desempenho

- Use Safari/iOS atualizado com **WebGL 2 e WebAssembly** habilitados. A compatibilidade final depende do aparelho e da versão do sistema.
- Exportação **single-thread**; não requer `SharedArrayBuffer`, COOP/COEP ou service worker.
- A página respeita notch e indicador de início com `safe-area-inset-*`, bloqueia o scroll durante o toque e redimensiona o canvas ao girar.
- Landscape é uma preferência; o Safari pode exigir que você gire o aparelho manualmente. O shell orienta o usuário em portrait.
- Cena estática simples, sem iluminação dinâmica, navegação, áudio, texturas grandes ou lógica de tráfego. Somente jogador, câmera e controles são atualizados continuamente.
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
  main.gd                    Conecta joystick e jogador
  city.gd                    Planta do bairro, ruas, decoração e limites
  building.gd                Bloco reutilizável; arte e colisão compartilham tamanho
  player_controller.gd       Movimento, desenho/animação e foco do jogador
  virtual_joystick.gd        Captura e interpretação de toque/mouse
  mobile_hud.gd              Layout da interface ao redimensionar
  parked_car.gd              Desenho do carro estacionado
world/
  city.tscn                  Cena do bairro e posições dos carros
  building.tscn              Construção StaticBody2D reutilizável
player/
  player.tscn                CharacterBody2D, colisão circular e Camera2D
vehicles/
  parked_car.tscn            Objeto visual, sem lógica de dirigir
ui/
  mobile_hud.tscn            CanvasLayer da interface
  virtual_joystick.tscn      Controle reutilizável
assets/
  icon.svg                   Ícone original do projeto
web/
  shell.html                 Página de carregamento adaptada ao Safari
tools/
  export_web.sh              Exportação por linha de comando
  serve_web.py               Servidor HTTP local para o build
tests/
  smoke_test.gd              Validação integrada do protótipo
build/web/                   Saída gerada pela exportação (não versionada)
.github/workflows/
  deploy-pages.yml           Build automático e publicação HTTPS no GitHub Pages
docs/
  GITHUB_PAGES.md             Configuração do Pages e acesso pelo iPhone
```

Arquivos `.uid` ao lado dos scripts são gerados pelo Godot para manter referências estáveis. A pasta `.godot/` é cache local e não precisa ser compartilhada.

O mapa usa `world/building.tscn` instanciado pela planta em `scripts/city.gd`. A colisão de cada construção acompanha seu `footprint`. O jogador aceita qualquer Node com `get_direction() -> Vector2`, mantendo o controle de toque independente. Para alterar o tamanho do mundo, ajuste também os limites da câmera em `player/player.tscn`.

## Verificação

Execute o teste integrado pelo terminal:

```bash
godot --headless --path . --script res://tests/smoke_test.gd
```

No iPhone, valide manualmente: andar nas oito direções; encostar nos quatro lados de um prédio; soltar e cancelar o toque; tocar na direita com outro dedo; girar a tela; alternar apps e voltar; caminhar pelos limites do bairro e observar a câmera. A câmera deve continuar alinhada ao mapa e nenhum dedo solto deve deixar o personagem andando.

O teste automatizado e a exportação podem ser validados em navegador neste ambiente, mas não substituem o teste em um iPhone físico. Não foi medida uma taxa de FPS em hardware iOS.
