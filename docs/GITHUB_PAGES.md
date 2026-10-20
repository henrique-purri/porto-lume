# Jogar no Safari do iPhone pelo GitHub Pages

O projeto está preparado para uma URL pública HTTPS. Não precisa de computador
na mesma rede, servidor local ou backend. A exportação usa **Godot 4.6.3 Standard,
Compatibility/WebGL 2 e WebAssembly sem threads**, compatível com hospedagem
estática no GitHub Pages sem cabeçalhos COOP/COEP.

**Jogo:** [https://henrique-purri.github.io/porto-lume/](https://henrique-purri.github.io/porto-lume/)

**Repositório:** [henrique-purri/porto-lume](https://github.com/henrique-purri/porto-lume),
branch `main`. O MVP já está publicado e foi validado pelo usuário no Safari do
iPhone. Pages usa **GitHub Actions** como origem; não é necessário habilitá-lo
novamente para atualizar o jogo.

## Atualizar a versão publicada

1. Envie as alterações para `main`, preservando `.github/workflows/deploy-pages.yml`,
   os testes, `tools/` e a configuração Web. Não envie caches `.godot/` ou `build/`.
2. Acompanhe [Actions](https://github.com/henrique-purri/porto-lume/actions). O push
   inicia **Build Web e publicar no GitHub Pages** automaticamente. Para repetir
   sem alterar o código, abra o workflow e use **Run workflow → main → Run workflow**.
3. Espere os jobs **Godot 4.6.3 · Web single-thread** e **Publicar jogo** ficarem
   verdes no commit desejado. A atualização do Protótipo 05 só está publicada depois
   da conclusão do segundo job.
4. Abra o endereço HTTPS do jogo no Safari. O mesmo link serve para todas as
   versões; recarregue a página para carregar a publicação mais recente.

Se o projeto estiver em `porto-lume/` dentro do repositório, o workflow também o
encontra. Porém **`.github/workflows/deploy-pages.yml` precisa ficar sempre na raiz
do repositório**, pois o GitHub não descobre workflows em subpastas do projeto.
Se a branch principal tiver outro nome, ajuste `branches: [main]` no workflow.

## Abrir e validar no iPhone

Abra a URL HTTPS no **Safari**, gire o aparelho para landscape, toque em
**Iniciar exploração** e mova o joystick à esquerda. Se necessário, desligue o bloqueio de
rotação. A primeira abertura baixa o runtime do Godot e pode demorar na rede
móvel. Mantenha o Safari/iOS atualizado para suporte a WebGL 2 e WebAssembly.

No Protótipo 05, aproxime-se do **carro coral** e toque em **ENTRAR**, à direita.
Use o joystick horizontal para virar e mantenha **ACELERAR** pressionado com
outro dedo. **FREAR / RÉ** primeiro para o veículo e depois recua, se continuar
pressionado. Soltar os pedais produz desaceleração progressiva. Arrastar o dedo
para fora de um pedal o libera; um novo toque é necessário para acioná-lo.

**SAIR** estaciona e procura espaço seguro ao lado do carro. Se não houver
posição livre, o personagem permanece dentro e aparece **Sem espaço para sair**.
A mesma câmera acompanha o personagem a pé e o carro durante a direção.
O carro mostarda estacionado e carros civis do trânsito parado podem ser adquiridos
pelo mesmo botão; a primeira entrada é um furto. O carro coral e os veículos já
adquiridos não geram outro furto. Há duas vagas para carros extras do trânsito;
um carro abandonado só libera vaga após sair da câmera e ficar a mais de 900 unidades.

O jogo mantém até **dez pedestres simultâneos**, com roupas amarelas,
azuis, verdes e roxas, velocidades e acessórios variados. Eles escolhem destinos
próximos nas calçadas, fazem pausas e mudam de rota quando bloqueados. A população
acompanha o personagem a pé ou dirigindo; NPCs muito distantes são removidos e
recriados depois. Um carro em movimento nas proximidades provoca fuga.
Um contato causa apenas queda e knockback, seguidos de recuperação, sem sangue ou
sistema de dano. Os controles existentes continuam iguais.

O trânsito mantém até **seis veículos civis NPC** circulando pelas ruas, além
dos dois carros originais. O alvo é quatro a pé e seis dirigindo, conforme haja
pontos livres fora da câmera. Eles seguem faixas à direita, escolhem caminhos sem
retornos, fazem curvas e passam um por vez nos cruzamentos. Sensores à frente
reduzem a velocidade e param quando há outro carro ou obstáculo. Um bloqueio do
jogador faz o trânsito esperar, sem atravessar carros ou subir na calçada.
Carros civis com velocidade abaixo de 12 unidades por segundo podem ser
adquiridos; viaturas e carros em movimento continuam sem entrada.

Novos veículos surgem somente fora da câmera com margem de 160 unidades, entre
520 e 1400 unidades do corpo controlado, em pontos desocupados. A manutenção cria
no máximo um substituto a cada 0,8 segundo, após a população inicial de até quatro.
Veículos a mais de 1700 unidades são removidos somente fora da tela. O mesmo
gerenciador acompanha o personagem a pé ou o carro enquanto dirige.

O Protótipo 05 acrescenta **heat de zero a 240**, com uma estrela a partir de
1 ponto, duas a partir de 60 e três a partir de 140. Atropelar um pedestre soma
45, causar um novo impacto elegível contra um veículo soma 15 e adquirir um carro
civil pela primeira vez soma 65. Quedas e impactos têm intervalos por vítima para
impedir crimes repetidos a cada frame; uma batida exige aproximação e velocidade
relativa de pelo menos 45 unidades por segundo. Uma viatura bater no jogador
parado não atribui um crime ao jogador.

O HUD distingue **LIVRE**, **ESCONDIDO · PROCURADO** e **EM PERSEGUIÇÃO**, com
três estrelas geométricas. O alvo é uma viatura de patrulha em estado livre; a
resposta tem alvo de uma no wanted 1, duas no wanted 2 e quatro no wanted 3.
As viaturas seguem as ruas e os cruzamentos, perseguem o último ponto conhecido e tentam
interceptar por direções distintas nos níveis maiores. Viaturas já à frente do
alvo podem fazer uma breve espera na própria faixa para bloquear a rota, fora
dos cruzamentos. A visão tem alcance de 600 unidades e é bloqueada por
construções. A posição oculta não é transmitida
continuamente à polícia.

Viaturas novas usam os mesmos cuidados de criação fora da câmera: margem de
160 unidades, distância de 520 a 1400 unidades, espaço livre e até uma criação
por manutenção de 0,8 segundo. Enquanto há wanted, os pontos também precisam
ficar a até 900 unidades do último crime ou avistamento comunicado; a criação
não acompanha secretamente o movimento oculto do jogador. A remoção por distância, ou por redução da resposta,
acontece somente fora da tela. Para escapar, quebre a visão e evite novos crimes.
Após oito segundos nessas condições, o heat cai seis pontos por segundo e as
estrelas desaparecem progressivamente. Perder o foco suspende a simulação;
nenhum controle novo é necessário para crime ou perseguição.

Teste as oito direções a pé, direção com dois dedos, frenagem/ré, colisões,
entrada/saída, giro da tela e troca de app/retorno. No computador, use
**WASD/setas** e **E** para entrar/sair. O teste automatizado não substitui a
validação em um iPhone físico.

Observe também as caminhadas pelas calçadas e as colisões com construções.
Aproxime-se de um pedestre com o carro para verificar a fuga; encoste nele para
testar queda e recuperação. Explore outros quarteirões para conferir a renovação
da população. O limite, as decisões espaçadas e o grafo compartilhado reduzem o
trabalho por frame; as medições no ambiente Cloud não equivalem ao FPS de um iPhone.

Observe também carros fazendo curvas e esperando a vez nos cruzamentos. Bloqueie
uma faixa com o carro coral para testar a fila e libere a via para conferir a
retomada. Encoste em veículos NPC para conferir colisões, sem atravessamento, e
percorra a cidade para verificar que os carros novos aparecem fora da câmera.

Para uma verificação rápida do novo sistema, entre no carro mostarda estacionado
a noroeste do início e observe as estrelas do furto. Explore dirigindo e a pé,
confira a chegada das viaturas pelas ruas e use quarteirões como cobertura para
verificar escondido, queda das estrelas e retorno a livre. Observe também a
ausência de spawn policial dentro da câmera. Não há armas, prisão ou morte.

## O que a automação faz

- Usa a imagem **`barichello/godot-ci:4.6.3`**, fixada também por digest, com engine
  e templates oficiais já instalados. Não depende da instalação deste Codex Cloud.
- Confere a versão exata e os templates `web_nothreads_debug.zip` e
  `web_nothreads_release.zip`, importa o projeto e executa `tools/export_web.sh`.
- Executa `tests/smoke_test.gd`, `tests/vehicle_test.gd`,
  `tests/pedestrian_test.gd`, `tests/traffic_test.gd` e `tests/wanted_test.gd` para validar mapa,
  movimento, controles, direção, entrada/saída, população, rotas, obstáculos,
  fuga, knockback, cruzamentos, filas, colisões do trânsito, crimes,
  wanted, visibilidade policial, perseguição e perda da polícia.
- Verifica que HTML, JavaScript, WASM e PCK existem, confere as assinaturas dos
  binários e a sintaxe do JavaScript e inclui `.nojekyll`.
- Envia todo `build/web/` como artefato e publica pelo fluxo oficial do Pages.
  A exportação usa caminhos relativos, inclusive quando o site está sob
  `/porto-lume/`. Não há domínio ou URL absoluta codificada no jogo.

Um erro **Get Pages site failed / Not Found** no job de publicação geralmente
indica que falta selecionar **GitHub Actions** em Settings → Pages. Configure a
origem e execute o workflow novamente. Se a conta exigir aprovação de implantação
no ambiente `github-pages`, aprove a execução na página do workflow.

Para trocar a versão do Godot no futuro, atualize juntos o editor, os templates,
a tag/digest da imagem e as verificações de versão do workflow.
