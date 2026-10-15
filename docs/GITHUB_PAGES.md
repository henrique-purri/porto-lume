# Jogar no Safari do iPhone pelo GitHub Pages

O projeto está preparado para uma URL pública HTTPS. Não precisa de computador
na mesma rede, servidor local ou backend. A exportação usa **Godot 4.6.3 Standard,
Compatibility/WebGL 2 e WebAssembly sem threads**, compatível com hospedagem
estática no GitHub Pages sem cabeçalhos COOP/COEP.

**Repositório:** [henrique-purri/porto-lume](https://github.com/henrique-purri/porto-lume),
branch `main`. O projeto foi enviado e o build Web passou no GitHub Actions com
Godot e templates 4.6.3. O artefato `github-pages` contém o jogo exportado.
A publicação exige habilitar Pages nas configurações: a integração tem acesso
ao código e ao Actions, mas a API administrativa do Pages retorna 403.

O responsável pelo repositório deve abrir
[Settings → Pages](https://github.com/henrique-purri/porto-lume/settings/pages)
e escolher **GitHub Actions** em **Source**. Depois, repita o job de publicação
que falhou ou execute o workflow novamente. O repositório continua privado;
se o GitHub exigir um plano compatível, essa escolha cabe ao proprietário.

## Preparar o repositório uma única vez

1. Entre na sua conta em [github.com](https://github.com/) pelo Safari e crie um
   repositório, por exemplo **porto-lume**. Um repositório público pode usar Pages
   no plano gratuito. Para privado, confirme a disponibilidade no seu plano.
2. Coloque o conteúdo desta pasta na raiz do repositório, preservando os caminhos,
   incluindo a pasta oculta **`.github/`**, os testes e `tools/`. Não envie caches
   `.godot/`, ferramentas locais nem `build/`. A branch principal esperada é
   **`main`**.
3. A opção mais prática é abrir uma sessão Codex com esse repositório GitHub
   conectado e acesso de escrita para enviar os arquivos. Se usar **Add file →
   Upload files** no Safari, extraia qualquer ZIP antes no app Arquivos e preserve
   as pastas. Enviar apenas um ZIP para o repositório não instala o projeto nem
   ativa o workflow. O seletor de arquivos do iPhone pode limitar o envio de
   pastas; **Solicitar Site para Computador** pode facilitar a interface, mas não
   substitui o envio de cada arquivo com o caminho correto.
4. Abra **Settings → Pages → Build and deployment → Source** e escolha
   **GitHub Actions**. No iPhone, o menu **…** ou a versão para computador ajuda a
   encontrar Settings.
5. Em **Actions**, abra **Build Web e publicar no GitHub Pages** e toque em
   **Run workflow → main → Run workflow**. Faça isso após configurar Pages; os
   próximos pushes em `main` já iniciam tudo automaticamente.
6. Espere os jobs **Godot 4.6.3 · Web single-thread** e **Publicar jogo** ficarem
   verdes. Abra a URL do ambiente **github-pages** no resultado do workflow ou
   em **Settings → Pages → Visit site**.

A URL costuma ser `https://SEU_USUARIO.github.io/porto-lume/`. Use a URL exibida
pelo GitHub: o nome real da conta e do repositório determinam o endereço.

Se o projeto estiver em `porto-lume/` dentro do repositório, o workflow também o
encontra. Porém **`.github/workflows/deploy-pages.yml` precisa ficar sempre na raiz
do repositório**, pois o GitHub não descobre workflows em subpastas do projeto.
Se a branch principal tiver outro nome, ajuste `branches: [main]` no workflow.

## Abrir e validar no iPhone

Abra a URL HTTPS no **Safari**, gire o aparelho para landscape, toque em
**Iniciar** e mova o joystick à esquerda. Se necessário, desligue o bloqueio de
rotação. A primeira abertura baixa o runtime do Godot e pode demorar na rede
móvel. Mantenha o Safari/iOS atualizado para suporte a WebGL 2 e WebAssembly.

Teste as oito direções, colisão com prédios, acompanhamento da câmera, soltar o
joystick, tocar com outro dedo na direita e trocar de app/voltar. O teste
automatizado não substitui a validação em um iPhone físico.

## O que a automação faz

- Usa a imagem **`barichello/godot-ci:4.6.3`**, fixada também por digest, com engine
  e templates oficiais já instalados. Não depende da instalação deste Codex Cloud.
- Confere a versão exata e o template `web_nothreads_release.zip`, importa o
  projeto e executa `tools/export_web.sh` e `tests/smoke_test.gd`.
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
