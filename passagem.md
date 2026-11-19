# Passagem: limites dos planos no AllDocs e no AllPhotos

Sessão de 17/11/2026. O mesmo ficheiro está no AllDocs e no allphotos12.

Nada foi alterado no código. Isto é análise e proposta, à espera de decisão.

## Pergunta de partida

O limite do plano grátis deve ser por **número** (documentos ou fotos) em vez de **espaço**? O objetivo é vender o plano do meio: o Folio no AllDocs e o Premium no AllPhotos.

## Estado atual (lido no código)

### AllDocs (`ui/lib/models/plan.dart`, `PlanCatalog.builtIn`)

| Plano | Preço | Espaço | Lembretes | Dispositivos | Extras |
|---|---|---|---|---|---|
| Pocket (`free`) | grátis | 500 MB | 3 | 1 | nenhum |
| Folio (`premium`) | 1,99 €/mês, 15,99 €/ano | 5 GB | ilimitados | 2 | backup automático, marca de água, ferramentas PDF, cofre (álbuns ocultos) |
| Vault (`pro`) | 4,99 €/mês, 39,99 €/ano | 50 GB | ilimitados | 3 | o do Folio, mais sincronização, partilha segura, pedidos de documentos, assistente IA e suporte prioritário |

Tudo fica guardado no telemóvel, por isso o limite de espaço não corresponde a nenhum custo nosso.

Atenção: `~/Downloads/AllDocs-main` é uma cópia antiga, sem planos. Não a uses.

### AllPhotos (`Backend/src/lib/plans.ts`)

| Plano | Preço | Espaço | Álbuns | Prateleiras |
|---|---|---|---|---|
| Free | grátis | 1 GB | 10 | 2 |
| Premium | 0,99 €/mês | 5 GB | ilimitados | ilimitadas |
| Pro | 4,99 €/mês | 50 GB | ilimitados | ilimitadas |

- As fotos vão para o Google Drive do utilizador: `Backend/src/lib/storage.ts` chama `uploadPhotoToGoogleDrive`.
- Com o Drive ligado, o limite é a quota do Drive e não o do plano (`Backend/src/modules/plans/plans.service.ts`, `getStorageUsage`).
- Por isso, os 5 GB e 50 GB não contam para quem liga o Drive, e o Pro não se distingue do Premium.
- O CSV de utilizadores (`~/Downloads/database_users_allphotos*.csv`) tem cerca de 148 contas, mas não indica o plano de cada uma.

## Recomendação

### Princípio comum às duas apps

- O limite deve aparecer quando a pessoa já tirou valor da app, e não no primeiro dia.
- Nunca se bloqueia o acesso nem a exportação do que já está guardado. Bloqueia-se só a próxima ação.
- Quem já passa o novo limite fica com o que tem (direitos adquiridos). Os utilizadores são avisados antes da mudança.
- Aparece um aviso aos 80% do limite.
- O espaço deixa de ser argumento de venda e passa a limite técnico, sem destaque.

### AllDocs

| Limite | Pocket | Folio | Notas |
|---|---|---|---|
| Lembretes de validade | 3 | ilimitados | É o gatilho principal. Contam só documentos com validade. |
| Documentos | 40 a 50 | ilimitados | Rede de segurança. |
| Perfis de família | 1 | 4 (Vault 8) | Função nova. |
| Cofre com PIN | teste com 3 documentos | completo | |
| Espaço | 500 MB | 5 GB | Mantém-se, mas não se anuncia. |

Os números por pessoa são estimativas sem fonte. Uma pessoa tem entre 5 e 8 documentos com validade, e uma família entre 15 e 25.

### AllPhotos

- Contar só as fotos organizadas no AllPhotos (álbuns, prateleiras e caixa). A galeria do telemóvel não conta.
- Proposta, com números a confirmar pelos dados:
  - Free: 1 000 fotos, mais 10 a 15 álbuns.
  - Premium: 10 000 fotos.
  - Pro: fotos ilimitadas, mais funções próprias (partilha familiar, mais dispositivos). Sem isto, o Pro deixa de fazer sentido.
- Limitar por número acompanha o custo real, que são as chamadas à API do Drive e as linhas na base de dados.

### Preços (para testar em A/B, não para mudar já)

- Folio a 2,49 €/mês ou 19,99 €/ano, em vez de 1,99 € ou 15,99 €. O plano anual aparece primeiro: "1,67 €/mês, pago anualmente, 2 meses grátis".
- Vault a 6,99 €/mês ou 49,99 €/ano. Serve de isca para fazer o Folio parecer barato.
- A sincronização fica no Vault, porque é a única função com custo de servidor. O Folio precisa de restauro simples num telemóvel novo.
- O AllPhotos Premium está barato (0,99 €) face ao Folio (1,99 €) e dá mais. O AllPhotos Pro custa o mesmo que o Vault (4,99 €) e dá menos.
- Conflito de nomes: o Vault ("cofre") e o cofre que já vem no Folio. Decidir o nome ou a mensagem de cada um.
- Bundle "All\* Duo" (Folio mais AllPhotos Premium) por cerca de 2,49 €/mês. Só avança se houver dados de quantas pessoas usam as duas apps.

### Concorrência (fontes de terceiros, confirmar nas lojas portuguesas)

| App | Plano grátis | Preço pago |
|---|---|---|
| Genius Scan | sem limite de scans nem marca de água | Plus a cerca de 9,99 USD (OCR e sincronização pagos) |
| CamScanner | com anúncios, marca de água e cerca de 10 OCR | 9,99 USD/mês, entre 39,99 e 79,99 USD/ano |
| SwiftScan | sem limite de scans | 5,99 USD/mês, 34,99 USD/ano |
| Scanner Pro | teste de 7 dias | cerca de 31,99 €/ano (França) |
| Trustworthy (cofre) | 2 GB e 1 familiar | 10 a 20 USD/mês |

Os scanners limitam funções (OCR, sincronização, anúncios) e não o número de documentos.

## Ideias para converter em Folio (esforço entre parêntesis)

1. Caducidade detetada pelo OCR a menos de 90 dias: "O teu CC caduca em 2 meses". Se não houver lembretes livres, abre o paywall (baixo).
2. Fatura de eletrónica ou eletrodoméstico propõe um lembrete de garantia (baixo).
3. Ao fim de 30 dias sem backup: "Se perderes o telemóvel, perdes tudo" (baixo).
4. Privacidade: "Os teus documentos nunca passam pelos nossos servidores". Só se continuar a ser verdade (baixo).
5. Dossier IRS de janeiro a junho, com faturas de saúde, educação e despesas gerais num só PDF. Validar com um contabilista (médio).
6. Dossiers de carro e de arrendamento, com lembretes agrupados (médio).
7. Perfis de família: o OCR deteta outro titular e pergunta "Criar perfil para…?" (médio a alto).
8. Teste do Folio durante 7 dias, oferecido quando se atinge o limite e nunca no primeiro dia. Dia 1: lembretes. Dia 2: PDF. Dia 3: cofre. Dia 6: "Termina amanhã".
9. Referral: 1 mês de Folio para quem convida e para quem entra. Confirmar antes as regras da Apple e da Google.
10. Calendário em Portugal: Black Friday a 27/11/2026 ("guarda a garantia do presente"), janeiro para arrumar o ano, IRS de 1 de abril a 30 de junho, regresso às aulas em setembro.

### Textos de exemplo para o limite

- Barra: "38 de 50 documentos no Pocket". Muda de cor só a partir dos 80% e nunca fica vermelha.
- Ecrã do limite: "Chegaste a 50 documentos. Os que já guardaste continuam aqui. Para guardar mais, passa ao Folio."

## Próximos passos

1. **Medir.** Registar os eventos "limite atingido", "paywall visto", "teste iniciado" e "pago", separados por tipo de limite e por dia desde a instalação. Tirar a distribuição por plano das duas apps.
2. **AllPhotos.** Correr esta query no Postgres de produção para fixar os limites. A regra é pôr o limite do Free perto do p90 dos utilizadores gratuitos.

   ```sql
   SELECT p.plan,
          COUNT(*) AS utilizadores,
          percentile_cont(0.5) WITHIN GROUP (ORDER BY n) AS mediana,
          percentile_cont(0.9) WITHIN GROUP (ORDER BY n) AS p90,
          MAX(n) AS maximo
   FROM (SELECT user_id, COUNT(*) AS n FROM photos GROUP BY user_id) f
   JOIN profiles p ON p.id = f.user_id
   GROUP BY p.plan;
   ```

3. **Mudar os gatilhos.** No AllDocs: lembretes, mais 40 a 50 documentos, mais o cofre de teste. No AllPhotos: número de fotos organizadas.
4. **Testar o preço.** Folio a 2,49 € contra 1,99 €, com o anual primeiro. Com tão poucos utilizadores, o teste vai demorar semanas.

## Por verificar

- Onde ficam as fotos de quem está no Free do AllPhotos sem o Drive ligado.
- Os preços da concorrência nas lojas portuguesas.
- As regras de ofertas e referral da Apple e da Google.
- Os prazos de garantia no DL 84/2021, antes de os usar em conteúdo.
- Os dados reais de conversão. Os números propostos são hipóteses.

## Decisões pendentes (tuas)

- [ ] Que eixo usar no AllDocs: lembretes mais documentos, ou só documentos.
- [ ] Que números ficam no Pocket e no Free do AllPhotos.
- [ ] Se se testa a subida de preço do Folio e do Vault.
- [ ] Que funções próprias dar ao AllPhotos Pro.
- [ ] O nome do Vault ou a mensagem do cofre.
- [ ] Se se avança com o bundle "All\* Duo".

## Decisão (19/11/2026)

Aplicado no código: o Pocket guarda até 10 documentos (a reciclagem não conta), o Folio e o Vault não têm limite de documentos, e o limite de espaço saiu dos planos (`maxDocuments` em `ui/lib/models/plan.dart` e `Backend/src/lib/plans.ts`). Lembretes, dispositivos e funcionalidades ficaram iguais.
