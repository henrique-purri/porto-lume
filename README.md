# Porto Lume — Protótipo 05 · Godot 2D

Protótipo original de exploração urbana top-down para smartphones. Feito em **Godot 4.6.3, GDScript e renderer Compatibility (WebGL 2)**. Gráficos são placeholders geométricos desenhados no Godot, sem dependências de arte ou plugins.

## O que está funcionando

- Pequeno bairro de 2400 × 1800 unidades: ruas, faixas de pedestres, calçadas, pátios e 18 construções com colisão.
- Personagem com oito direções, velocidade diagonal normalizada e câmera com acompanhamento suave.
- Joystick touchscreen fixo no canto inferior esquerdo, com deadzone e captura de um dedo. Soltar/cancelar o toque, mudar a orientação ou perder o foco libera o controle.
- Carro coral original controlável, com aceleração, freio/ré, direção arcade, desaceleração progressiva e colisão com construções, limites e obstáculos.
- Segundo carro estacionado e carros civis do trânsito parado podem ser adquiridos pelo mesmo botão de entrada; entrar pela primeira vez conta como furto.
- Botão contextual **ENTRAR/SAIR**, pedais touchscreen independentes e câmera suave que acompanha o jogador ou o carro.
- Saída do veículo em uma posição livre próxima; se não houver espaço seguro, o jogador permanece dentro.
- Até **10 pedestres ativos**, andando nas calçadas, com velocidades, cores de roupa, bonés, mochilas e tons de pele variados.
- Pedestres desviam dos carros em movimento. Um contato produz apenas queda e knockback; depois eles se levantam e voltam a andar.
- Trânsito com até **6 veículos NPC ativos**, seguindo faixas, fazendo curvas nos cruzamentos e esperando outros carros. Cores, velocidades, aceleração e distância de seguimento variam.
- Wanted de **zero a três estrelas**, com heat por crime, indicadores **LIVRE**, **ESCONDIDO · PROCURADO** e **EM PERSEGUIÇÃO**.
- Viaturas usam as ruas e os cruzamentos existentes; até quatro podem perseguir ou tentar interceptar o jogador a pé ou dirigindo.
- Interface adaptável ao tamanho da tela e prioridade landscape. Controles liberam os toques ao perder foco ou mudar a orientação.
- Teclado WASD/setas e **E** para entrar/sair; também é possível arrastar o joystick e pressionar os botões com o mouse.

O personagem tem uma jaqueta coral e começa na rua ao sul do cruzamento central. O mapa, os nomes e os elementos visuais são originais. Esta versão ainda não inclui armas, tiros, combate complexo, prisão, morte do jogador, ambulâncias, helicópteros, missões ou dinheiro.

## Como dirigir

1. Caminhe até o carro coral. O botão **ENTRAR** aparece à direita quando o personagem está perto e consegue alcançar o veículo.
2. Toque em **ENTRAR**. O personagem fica oculto, a mesma câmera passa a seguir o carro e aparecem os pedais.
3. Mantenha **ACELERAR** pressionado e mova o joystick para a esquerda ou direita para virar. O eixo vertical do joystick não acelera o veículo.
4. Use **FREAR / RÉ** para parar. Mantenha o pedal pressionado após parar para recuar; a direção acompanha o sentido da marcha. Se os dois pedais estiverem pressionados, o freio tem prioridade.
5. Solte os pedais para desacelerar gradualmente. Arrastar o dedo para fora de um pedal também o libera; é preciso um novo toque para pressioná-lo novamente.
6. Toque em **SAIR** para estacionar e procurar uma posição segura ao lado do carro. Sem espaço livre, a mensagem **Sem espaço para sair** aparece e o jogador permanece dentro.

O mesmo botão permite entrar no carro mostarda estacionado e em carros civis do trânsito que estejam parados, com velocidade abaixo de 12 unidades por segundo. A primeira entrada em um carro que não seja o coral conta como furto. Viaturas e carros em movimento não podem ser adquiridos. Voltar a um veículo já adquirido não gera outro furto. Há um limite de dois carros extras adquiridos do trânsito; carros abandonados podem ser removidos somente fora da câmera e a mais de 900 unidades do corpo controlado, liberando uma vaga.

No teclado, **W/↑** acelera, **S/↓** freia e recua, **A/D** ou **←/→** viram e **E** entra/sai. A pé, WASD/setas continuam movendo o personagem nas oito direções.

## Pedestres

A população acompanha o personagem a pé ou o carro controlado. O limite é de **10 NPCs simultâneos**: eles surgem em pontos livres das calçadas entre 150 e 760 unidades do corpo controlado. A cada 0,75 segundo, o gerenciador remove os que estão a mais de 1100 unidades e cria até dois substitutos; a população inicial pode preencher o limite de uma vez. Isso mantém o trabalho limitado enquanto o jogador explora a cidade. Ao perder o foco, a simulação dos pedestres é suspensa.

O grafo compartilhado tem **192 pontos nas calçadas** ao redor dos seis quarteirões e **42 pontos em passagens internas** para retomar a rota após um deslocamento. Cada pedestre escolhe um destino próximo, caminha por dois a cinco saltos do grafo e faz pequenas pausas. As velocidades variam entre **45 e 72 unidades por segundo**; camisetas amarelas, azuis, verdes e roxas distinguem os pedestres do jogador coral. Física e colisões impedem atravessar prédios, o jogador e carros. Um caminho bloqueado provoca parada e nova escolha de direção.

As decisões são distribuídas em intervalos de **0,18 a 0,28 segundo** por NPC. Um carro em movimento a menos de aproximadamente **150 unidades**, seja do jogador ou do trânsito, provoca uma tentativa de fuga pela calçada, com velocidade multiplicada por **1,85**. No contato, o pedestre cai e recebe um impulso amortecido. A queda dura cerca de **um segundo**, sem sangue, pontos de vida ou dano; se houver um carro sobre ele, espera ou se afasta antes de levantar. Um intervalo de **1,6 segundo** entre reações evita quedas repetidas no mesmo contato. Ao se recuperar, ele retorna às rotas normais.

## Trânsito civil

O limite é de **6 veículos NPC simultâneos**, além dos dois carros originais, das viaturas e dos veículos civis já adquiridos pelo jogador. O alvo da população é **4 a pé** e **6 ao dirigir**, podendo ficar abaixo disso quando não há pontos seguros disponíveis. O gerenciador acompanha o corpo controlado e cria no máximo um substituto por manutenção, a cada **0,8 segundo**. A população inicial pode criar até quatro veículos.

O grafo compartilhado usa **12 cruzamentos**, em uma grade de quatro colunas por três linhas, com as posições das ruas existentes. Cada sentido ocupa uma faixa deslocada **32 unidades à direita** do eixo da rua. Os carros escolhem o próximo vizinho sem fazer retorno, com uma pequena preferência por seguir reto. Segmentos retos e curvas quadráticas amostradas ligam as faixas; os trajetos mantêm o corpo do veículo sobre o asfalto. As velocidades de cruzeiro variam entre **100 e 145 unidades por segundo**, e a aceleração entre **75 e 120**. A distância desejada e o tempo de seguimento também variam.

Uma fila por cruzamento libera **um veículo por vez**. O carro aguarda antes da entrada, só entra quando a saída tem espaço e mantém a reserva até a traseira deixar a área do cruzamento. Sensores à frente atualizados em intervalos distribuídos de **0,10 a 0,16 segundo** reduzem a velocidade ou param diante de carros, pedestres e obstáculos. Se o jogador bloquear a rua, o trânsito aguarda; não troca de faixa nem atravessa o bloqueio. Colisões físicas impedem a sobreposição entre veículos. Os civis mantêm o comportamento de circulação e espera; a perseguição é coordenada pela polícia.

Os pontos de criação ficam em trechos retos, fora da câmera real com uma margem de **160 unidades**, a pelo menos **520 unidades** do corpo controlado e dentro de um raio de **1400**. Uma consulta física rejeita locais ocupados e mantém distância dos demais carros. Veículos a mais de **1700 unidades** podem ser removidos somente quando estão fora da tela. Reduções da população também preservam os carros visíveis. Se não houver local elegível, o gerenciador espera a próxima manutenção; nenhum carro precisa surgir dentro da câmera para preencher o limite.

`traffic_routes.gd` contém a geometria e as escolhas de rota; `traffic_manager.gd` mantém população e prioridade nos cruzamentos; `traffic_vehicle.gd` controla a condução de cada NPC. As viaturas reutilizam essa condução e a mesma prioridade nos cruzamentos, acrescentando escolhas de destino de patrulha e perseguição. A separação permite outros tipos de veículos futuramente sem alterar os controles.

## Crimes, heat e polícia do Protótipo 05

O `CrimeSystem` recebe eventos de gameplay e mantém **heat entre zero e 240**. As estrelas usam os limites **1 / 60 / 140** para os níveis **1 / 2 / 3**. A classificação de crimes é um registro separado: módulos futuros podem cadastrar outro tipo com severidade e intervalo próprios por `register_crime_type()`.

| Crime detectado | Heat | Quando conta |
| --- | ---: | --- |
| Atropelamento | 45 | O veículo controlado pelo jogador provoca uma queda aceita de um pedestre; a reação tem intervalo de 1,6 segundo por vítima. |
| Colisão com veículo | 15 | Um novo impacto causado pelo jogador tem componente de aproximação e velocidade relativa de pelo menos 45 unidades por segundo; há intervalo de 1,2 segundo por veículo atingido. |
| Furto de veículo | 65 | Primeira entrada no segundo carro estacionado ou em um carro civil parado que ainda não pertence ao jogador. |

Empurrar um carro continuamente não gera heat a cada frame. Contatos provocados apenas por uma viatura ou pelo trânsito contra o carro parado do jogador não são atribuídos ao jogador. Batidas repetidas precisam de separação e de um novo impacto elegível. Entrar no carro coral inicial e voltar a um carro já adquirido são ações livres.

O HUD mostra três estrelas geométricas e um estado por texto e cor: **LIVRE** quando o heat é zero, **EM PERSEGUIÇÃO** enquanto pelo menos uma viatura vê o corpo controlado e **ESCONDIDO · PROCURADO** quando ainda há heat, mas a polícia perdeu a visão. A visão usa distância de até **600 unidades** e uma consulta física bloqueada por construções. A posição procurada é atualizada por crimes e observações reais; a polícia não recebe continuamente a posição oculta do jogador.

O alvo é uma viatura em patrulha enquanto o jogador está livre. O alvo de resposta é **uma viatura no nível 1**, **duas no nível 2** e **quatro no nível 3**, com teto de quatro ativas. No nível 1, a viatura busca o último ponto conhecido pelas ruas. Nos níveis 2 e 3, perfis mais rápidos e diferentes pontos de interceptação tentam bloquear a rota e aproximar a polícia por direções distintas. Uma viatura já à frente do alvo observado pode aguardar na própria faixa por até dois segundos no nível 2 ou três no nível 3, com intervalo de oito segundos entre tentativas; esse bloqueio só acontece em trecho reto, fora do cruzamento e sem reserva ativa. A condução continua usando faixas, curvas, sensores e reservas de cruzamento; não há passagem por prédios ou teletransporte até o jogador. A perseguição acompanha o personagem a pé ou o carro atualmente controlado. Se o personagem entrar em uma área de pedestres, as viaturas procuram acesso pelas ruas próximas.

O spawn policial segue pontos livres fora da câmera real, com margem de **160 unidades**, distância mínima de **520** e raio de até **1400** unidades. Enquanto há wanted, os reforços também ficam a até **900 unidades do último crime ou avistamento comunicado**, evitando usar o movimento oculto do jogador como destino de criação. A reposição cria no máximo uma viatura a cada **0,8 segundo**. Viaturas a mais de **1700 unidades**, ou excedentes após a redução do wanted, só são removidas fora da tela; o gerenciador pode adiar uma criação ou remoção para preservar essas condições.

Para escapar, interrompa novos crimes e quebre a linha de visão, por exemplo contornando um quarteirão e buscando cobertura. Após **oito segundos sem visão policial e sem novos crimes**, o heat cai **seis pontos por segundo**. As estrelas desaparecem ao cruzar cada limite, e o estado volta a **LIVRE** ao chegar a zero. Uma nova observação ou crime interrompe a redução e reinicia a espera. Perder o foco do Safari suspende a simulação em vez de conceder fuga em segundo plano.

## Abrir no Godot

1. Instale o **Godot 4.6.3 Standard**, sem necessidade de .NET.
2. Importe `project.godot` no gerenciador de projetos.
3. Pressione **F6** para executar uma cena aberta ou **F5** para o jogo completo.

Use o renderer **Compatibility**. O renderer chamado “Mobile” no Godot não é o renderer desta versão Web.

## Jogar no Safari pelo GitHub Pages

O MVP já está publicado em **[https://henrique-purri.github.io/porto-lume/](https://henrique-purri.github.io/porto-lume/)** e foi validado pelo usuário no Safari do iPhone. Não é necessário computador, localhost ou Wi-Fi local. O fluxo completo está em [docs/GITHUB_PAGES.md](docs/GITHUB_PAGES.md).

O workflow `.github/workflows/deploy-pages.yml` constrói o jogo com **Godot 4.6.3 e templates da mesma versão** em ambiente preparado, verifica os arquivos exportados e publica no Pages a cada atualização da branch `main`. Também pode ser iniciado manualmente pela aba Actions. O Pages precisa usar **GitHub Actions** como origem em **Settings → Pages**.

Abra o endereço acima no Safari do iPhone, gire o aparelho para landscape e toque em **Iniciar exploração**. Desative o bloqueio de rotação se necessário. A atualização do Protótipo 05 ficará disponível nesse mesmo endereço depois que os jobs de build e publicação do respectivo commit estiverem verdes.

O repositório do projeto é [henrique-purri/porto-lume](https://github.com/henrique-purri/porto-lume), na branch `main`. Não abra o HTML pelo app Arquivos: o Godot precisa servir também JavaScript, WebAssembly e o pacote do jogo por HTTP/HTTPS.

O [GitHub Actions](https://github.com/henrique-purri/porto-lume/actions) confere Godot e templates **4.6.3**, executa os cinco testes integrados e verifica HTML, JS, WASM e PCK. O artefato `github-pages` contém o build completo. O Pages já está configurado; cada push em `main` inicia uma nova publicação. O resultado de cada atualização aparece nos jobs **Godot 4.6.3 · Web single-thread** e **Publicar jogo**.

A exportação usa caminhos relativos, funciona em subpastas do Pages e não requer backend ou cabeçalhos de isolamento de origem. O servidor `tools/serve_web.py` fica disponível apenas para desenvolvimento; ele não faz parte do acesso pelo iPhone.

### Safari e desempenho

- Use Safari/iOS atualizado com **WebGL 2 e WebAssembly** habilitados. A compatibilidade final depende do aparelho e da versão do sistema.
- Exportação **single-thread**; não requer `SharedArrayBuffer`, COOP/COEP ou service worker.
- A página respeita notch e indicador de início com `safe-area-inset-*`, bloqueia o scroll durante o toque e redimensiona o canvas ao girar.
- Landscape é uma preferência; o Safari pode exigir que você gire o aparelho manualmente. O shell orienta o usuário em portrait.
- Cena simples, sem iluminação dinâmica, bake de navegação, áudio ou texturas grandes. Pedestres, trânsito e polícia usam grafos pequenos, têm limites de população e decisões distribuídas. Sensores usam consultas físicas curtas; não há planejamento de rotas sobre a cidade inteira a cada frame.
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
  main.tscn                  Composição: mundo + jogador + populações + crime + HUD
scripts/
  main.gd                    Conecta jogador, HUD, veículos e população
  city.gd                    Planta do bairro, ruas, decoração e limites
  building.gd                Bloco reutilizável; arte e colisão compartilham tamanho
  player_controller.gd       Movimento, desenho/animação e foco do jogador
  virtual_joystick.gd        Captura e interpretação de toque/mouse
  mobile_hud.gd              Layout, ação contextual e controles de direção
  touch_action_button.gd     Botão de toque com captura independente por dedo
  vehicle_controller.gd      Direção arcade, frenagem, ré e colisão do carro
  vehicle_interaction.gd     Entrada, saída segura e transferência da câmera
  parked_car.gd              Desenho compartilhado pelos carros
  pedestrian.gd              Caminhada, aparência, fuga, queda e recuperação
  pedestrian_paths.gd        Grafo compartilhado de calçadas e rotas próximas
  pedestrian_manager.gd      Limite, criação e remoção da população local
  traffic_routes.gd          Grafo de faixas, pontos de criação e curvas
  traffic_vehicle.gd         Condução, frenagem, sensores e espera de cada NPC
  traffic_manager.gd         População local, criação segura e cruzamentos
  vehicle_contacts.gd        Contato compartilhado dos veículos com pedestres
  crime_system.gd            Registro de crimes, heat, estrelas e fuga
  police_manager.gd          Resposta limitada, observações e spawn policial
  police_vehicle.gd          Patrulha, perseguição e interceptação pelas ruas
  police_visual.gd           Aparência e luzes simples da viatura
world/
  city.tscn                  Cena do bairro e posições dos carros
  building.tscn              Construção StaticBody2D reutilizável
player/
  player.tscn                CharacterBody2D, colisão circular e Camera2D
npc/
  pedestrian.tscn            Pedestre reutilizável, com colisão circular
vehicles/
  driveable_car.tscn         Carro coral controlável, com corpo e colisão
  parked_car.tscn            Base visual do carro estacionado original
  traffic_car.tscn           Veículo NPC reutilizável com colisão física
  police_car.tscn            Viatura reutilizando a condução de trânsito
ui/
  mobile_hud.tscn            CanvasLayer da interface
  wanted_display.gd          Estrelas geométricas e estado de perseguição
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
  pedestrian_test.gd         População, rotas, obstáculos, fuga e knockback
  traffic_test.gd            Faixas, cruzamentos, filas, colisões e população
  wanted_test.gd             Crimes, heat, furtos, polícia, visão e fuga
build/web/                   Saída gerada pela exportação (não versionada)
.github/workflows/
  deploy-pages.yml           Build automático e publicação HTTPS no GitHub Pages
docs/
  GITHUB_PAGES.md             Configuração do Pages e acesso pelo iPhone
```

Arquivos `.uid` ao lado dos scripts são gerados pelo Godot para manter referências estáveis. A pasta `.godot/` é cache local e não precisa ser compartilhada.

O mapa usa `world/building.tscn` instanciado pela planta em `scripts/city.gd`. A colisão de cada construção acompanha seu `footprint`. O jogador aceita qualquer Node com `get_direction() -> Vector2`; o veículo consulta `get_drive_throttle()` e `get_drive_steering()` no HUD. `vehicle_interaction.gd` coordena a troca de controle, mantém a mesma câmera e verifica posições de saída com a física do mundo. Para alterar o tamanho do mundo, ajuste também os limites da câmera em `player/player.tscn` e `world_bounds` no sistema de interação.

`pedestrian_manager.gd` controla a população e compartilha uma instância de `pedestrian_paths.gd` entre os NPCs. `pedestrian.gd` mantém os estados de caminhada, pausa, fuga e queda. Os pedestres usam a camada física 4 (valor de máscara 8); jogador, veículos e verificações de saída mantêm as colisões e posições seguras. Todos os carros usam a camada física 3 (valor 4), permitindo que os sistemas atuais reconheçam o trânsito como obstáculo. A interação mantém o mesmo controle de entrada/saída ao adquirir um carro civil e registra o furto uma única vez por veículo. A separação entre população, rotas e comportamento permite ampliar os sistemas sem alterar os controles atuais.

## Verificação

Execute os cinco testes integrados pelo terminal:

```bash
godot --headless --path . --script res://tests/smoke_test.gd
godot --headless --path . --script res://tests/vehicle_test.gd
godot --headless --path . --script res://tests/pedestrian_test.gd
godot --headless --path . --script res://tests/traffic_test.gd
godot --headless --path . --script res://tests/wanted_test.gd
```

No iPhone, valide andar nas oito direções, aproximar-se do carro coral e entrar, usar joystick e pedal com dedos diferentes, frear até engatar ré, soltar os pedais e sair. Encoste o carro em prédios, limites e no carro estacionado; tente sair com um lado bloqueado. Gire a tela e alterne apps durante o controle. A câmera deve seguir o corpo ativo sem girar o mapa, e nenhum dedo solto deve deixar um controle pressionado.

Observe os pedestres caminhando e fazendo pausas nas calçadas. Aproxime o carro para verificar a fuga e encoste em um pedestre para observar queda, afastamento e recuperação. Percorra os quarteirões a pé e dirigindo: novos pedestres podem aparecer na região, mas o total ativo nunca deve ultrapassar dez. Nenhum pedestre deve atravessar construções, e sair do veículo deve continuar exigindo uma posição livre.

Observe o trânsito fazendo curvas e esperando nos cruzamentos. Pare o carro coral na faixa para conferir a frenagem e a formação de fila; depois libere a via e verifique se os veículos retomam o caminho. Teste o contato entre carros sem atravessamento e a saída segura ao lado de um veículo NPC. Explore o mapa a pé e dirigindo, verificando que carros só aparecem fora da câmera e que o limite de seis é respeitado. A suíte de trânsito mede também o custo de física com a população limitada; o valor no Cloud não representa FPS em hardware iOS.

Para validar o wanted no iPhone, entre no carro mostarda estacionado a noroeste do início: a primeira entrada gera heat e estrelas. Confira a reação das viaturas e o indicador de perseguição, tanto dirigindo quanto após sair do veículo. Faça novos crimes para aumentar a resposta e depois busque cobertura sem novos crimes: observe a transição para escondido, a redução progressiva das estrelas e o retorno a livre. Confira que nenhuma viatura aparece ao lado do personagem e que as colisões e os controles continuam funcionando.

O teste automatizado e a exportação podem ser validados em navegador neste ambiente, mas não substituem o teste em um iPhone físico. Não foi medida uma taxa de FPS em hardware iOS.
