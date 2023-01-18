> Instalar container (docker-compose up);
> Iniciar container (run-docker.sh);
> Instalar pacotes do R;
> Rodar a pipeline (run.sh/run.R);
> Configurar parâmetro do PBI e atualizar dados.

Pacotes usados: targets, tarchetypes, RPostgres, DBI, dbplyr, tidyverse, timetk, modeltime, 
tidymodels, lubridate.
I. Inicialmente é feita a configuração do ambiente no Docker para conectar com a base de dados 
(seguindo os passos do vídeo). Um script shell pode ser usado para inicializar o container.
Obs.: Mesmo tentando de diversas formas, só consegui acessar a base com o usuário do 
postgres, ao tentar com o usuário docker não carregava os dados.

II. Em seguida, são criados o(s) script(s) em R (dplyr) para extração das tabelas necessárias.
Obs.: Pode-se usar scripts em SQL porém foi percebido que nem sempre é a opção mais rápida.
	1. Fluxo global da cadeia.
		Localização e informações de fornecedores, fábricas, lojas e centros de distribuição.
			.
	2. Benchmarking de produtos.
		Identificação de produtos mais e menos lucrativos.
			Para identificar a lucratividade dos produtos é necessário entender o valor
			de produção de cada produto assim como seu valor de venda, calculando o 
			lucro por produto.
			Pode-se investigar também quais produtos geraram mais lucro com base nos dados
			de vendas, multiplicando a quantidade de pedidos pelo lucro bruto do produto.
			Tabela production.product
	
	3. Projeção histórica de venda e previsão futura.
		Desenvolvimento de modelos de demanda por região/produto
			Neste caso pode-se obter a projeção histórica por região a partir da 
			tabela sales.salesorderheader. E, por produto, juntando-a com a 
			sales.salesorderdetail.
			A equação de demanda é uma expressão matemática que relaciona a quantidade 
			demandada de um bem e fatores que afetam a iniciativa do consumidor em 
			comprar esse bem, como preço ou renda.
			Para o modelo de demanda por região...
			Como existem mais de 250 produtos, talvez não seja prático fazer um modelo de
			demanda para cada um. Por isso são escolhidos os quatro produtos mais pedidos.

Após isso é realizada a configuração do orquestrador de pipeline (targets) para:
	Conectar com a base de dados;
	Ingestão crua das tabelas de dados necessárias;
	Transformar os dados de forma analítica para responder as dúvidas;
	Geração de modelos de séries temporais para previsão;
	Salvar os dados em Parquet.

III. Então, gera-se o relatório em PBI para apresentar os dados de forma clara e intuitiva 
com descrição e comentários esclarecendo as dúvidas.
	O arquivo dashboard.pbix irá ler os dados gerados pela pipeline (.\_targets\objects\)
	e carregar as visualizações adequadas. É necessário alterar o valor do parâmetro para
	localizar a pasta do projeto na primeira vez (Transformar Dados > Editar Parâmetros). 
	Com o parâmetro correto os dados serão atualizados e carregados para o relatório.


	
	