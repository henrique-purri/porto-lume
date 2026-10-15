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
   verdes no commit desejado. A atualização do Protótipo 03 só está publicada depois
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

No Protótipo 03, aproxime-se do **carro coral** e toque em **ENTRAR**, à direita.
Use o joystick horizontal para virar e mantenha **ACELERAR** pressionado com
outro dedo. **FREAR / RÉ** primeiro para o veículo e depois recua, se continuar
pressionado. Soltar os pedais produz desaceleração progressiva. Arrastar o dedo
para fora de um pedal o libera; um novo toque é necessário para acioná-lo.

**SAIR** estaciona e procura espaço seguro ao lado do carro. Se não houver
posição livre, o personagem permanece dentro e aparece **Sem espaço para sair**.
A mesma câmera acompanha o personagem a pé e o carro durante a direção.
O segundo carro é um obstáculo estacionado com colisão, sem interação.

O Protótipo 03 adiciona até **dez pedestres simultâneos**, com roupas amarelas,
azuis, verdes e roxas, velocidades e acessórios variados. Eles escolhem destinos
próximos nas calçadas, fazem pausas e mudam de rota quando bloqueados. A população
acompanha o personagem a pé ou dirigindo; NPCs muito distantes são removidos e
recriados depois. Um carro conduzido em movimento nas proximidades provoca fuga.
Um contato causa apenas queda e knockback, seguidos de recuperação, sem sangue ou
sistema de dano. Os controles existentes continuam iguais.

Teste as oito direções a pé, direção com dois dedos, frenagem/ré, colisões,
entrada/saída, giro da tela e troca de app/retorno. No computador, use
**WASD/setas** e **E** para entrar/sair. O teste automatizado não substitui a
validação em um iPhone físico.

Observe também as caminhadas pelas calçadas e as colisões com construções.
Aproxime-se de um pedestre com o carro para verificar a fuga; encoste nele para
testar queda e recuperação. Explore outros quarteirões para conferir a renovação
da população. O limite, as decisões espaçadas e o grafo compartilhado reduzem o
trabalho por frame; as medições no ambiente Cloud não equivalem ao FPS de um iPhone.

## O que a automação faz

- Usa a imagem **`barichello/godot-ci:4.6.3`**, fixada também por digest, com engine
  e templates oficiais já instalados. Não depende da instalação deste Codex Cloud.
- Confere a versão exata e os templates `web_nothreads_debug.zip` e
  `web_nothreads_release.zip`, importa o projeto e executa `tools/export_web.sh`.
- Executa `tests/smoke_test.gd`, `tests/vehicle_test.gd` e
  `tests/pedestrian_test.gd` para validar mapa, movimento, controles, direção,
  entrada/saída, limite de população, rotas, obstáculos, fuga e knockback.
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
