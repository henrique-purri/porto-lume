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
   verdes no commit desejado. A atualização do Protótipo 04 só está publicada depois
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

No Protótipo 04, aproxime-se do **carro coral** e toque em **ENTRAR**, à direita.
Use o joystick horizontal para virar e mantenha **ACELERAR** pressionado com
outro dedo. **FREAR / RÉ** primeiro para o veículo e depois recua, se continuar
pressionado. Soltar os pedais produz desaceleração progressiva. Arrastar o dedo
para fora de um pedal o libera; um novo toque é necessário para acioná-lo.

**SAIR** estaciona e procura espaço seguro ao lado do carro. Se não houver
posição livre, o personagem permanece dentro e aparece **Sem espaço para sair**.
A mesma câmera acompanha o personagem a pé e o carro durante a direção.
O segundo carro é um obstáculo estacionado com colisão, sem interação.

O jogo mantém até **dez pedestres simultâneos**, com roupas amarelas,
azuis, verdes e roxas, velocidades e acessórios variados. Eles escolhem destinos
próximos nas calçadas, fazem pausas e mudam de rota quando bloqueados. A população
acompanha o personagem a pé ou dirigindo; NPCs muito distantes são removidos e
recriados depois. Um carro em movimento nas proximidades provoca fuga.
Um contato causa apenas queda e knockback, seguidos de recuperação, sem sangue ou
sistema de dano. Os controles existentes continuam iguais.

O Protótipo 04 acrescenta até **seis veículos NPC** circulando pelas ruas, além
dos dois carros originais. O alvo é quatro a pé e seis dirigindo, conforme haja
pontos livres fora da câmera. Eles seguem faixas à direita, escolhem caminhos sem
retornos, fazem curvas e passam um por vez nos cruzamentos. Sensores à frente
reduzem a velocidade e param quando há outro carro ou obstáculo. Um bloqueio do
jogador faz o trânsito esperar, sem atravessar carros ou subir na calçada. Não é
possível entrar nos carros NPC; o carro coral continua sendo o veículo controlável.

Novos veículos surgem somente fora da câmera com margem de 160 unidades, entre
520 e 1400 unidades do corpo controlado, em pontos desocupados. A manutenção cria
no máximo um substituto a cada 0,8 segundo, após a população inicial de até quatro.
Veículos a mais de 1700 unidades são removidos somente fora da tela. O mesmo
gerenciador acompanha o personagem a pé ou o carro enquanto dirige.

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

## O que a automação faz

- Usa a imagem **`barichello/godot-ci:4.6.3`**, fixada também por digest, com engine
  e templates oficiais já instalados. Não depende da instalação deste Codex Cloud.
- Confere a versão exata e os templates `web_nothreads_debug.zip` e
  `web_nothreads_release.zip`, importa o projeto e executa `tools/export_web.sh`.
- Executa `tests/smoke_test.gd`, `tests/vehicle_test.gd`,
  `tests/pedestrian_test.gd` e `tests/traffic_test.gd` para validar mapa,
  movimento, controles, direção, entrada/saída, população, rotas, obstáculos,
  fuga, knockback, cruzamentos, filas e colisões do trânsito.
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
