# ==============================================================================
# SCRIPT DE SETUP INICIAL DO BANCO LOCAL
#
# Roda UMA VEZ para popular o sinan.duckdb a partir do PostgreSQL.
# Em produção, use o botão de sync do painel (update_tb_data()).
#
# Credenciais: defina no ~/.Renviron (nunca coloque senhas neste arquivo):
#   PG_DB=<nome_do_banco>
#   PG_HOST=<endereco_do_servidor>
#   PG_PORT=5432
#   PG_USER=<usuario>
#   PG_PASS=<senha>
# ==============================================================================

library(RPostgres)
library(DBI)
library(duckdb)

con_pg <- dbConnect(
  Postgres(),
  dbname   = Sys.getenv("PG_DB"),
  host     = Sys.getenv("PG_HOST"),
  port     = as.numeric(Sys.getenv("PG_PORT")),
  user     = Sys.getenv("PG_USER"),
  password = Sys.getenv("PG_PASS")
)

tb_sinan <- dbGetQuery(con_pg, "SELECT * FROM <schema>.\"<tabela_de_casos_georreferenciados>\"")

dbDisconnect(con_pg)

con_duck <- DBI::dbConnect(duckdb::duckdb(), "local/sinan.duckdb")

DBI::dbWriteTable(con_duck, "tb_sinan", tb_sinan, overwrite = TRUE)

DBI::dbExecute(con_duck, "create or replace table tb_sinan_treated as (
	select
	NU_NOTIFIC as numero_notificacao,
	DT_DIAG as dt_diagnostico,
	DT_NOTIFIC as dt_notificacao,
	try_cast(try_strptime(DT_INIC_TR, '%d/%m/%Y') as date) as dt_inicio_tratamento,
	try_cast(try_strptime(DT_ENCERRA, '%d/%m/%Y') as date) as dt_encerramento,
	case when SITUA_ENCE in (1,2,3,4,5,6,7,8,9,10) then 'Encerrado' else 'Em aberto' end as situacao,
	nm_pacient as nome_paciente,
	try_cast(try_strptime(DT_NASC, '%d/%m/%Y') as date) as dt_nasc,
	case
		when left(cast(NU_IDADE_N as varchar), 1) = 1 then cast(right(cast(NU_IDADE_N as varchar), 3) as integer)/8760
		when left(cast(NU_IDADE_N as varchar), 1) = 2 then cast(right(cast(NU_IDADE_N as varchar), 3) as integer)/365
		when left(cast(NU_IDADE_N as varchar), 1) = 3 then cast(right(cast(NU_IDADE_N as varchar), 3) as integer)/12
		when left(cast(NU_IDADE_N as varchar), 1) = 4 then cast(right(cast(NU_IDADE_N as varchar), 3) as integer)
	end as idade,
	cs_sexo as sexo,
	case
		when CS_RACA = 1 then 'Branca'
		when CS_RACA = 2 then 'Preta'
		when CS_RACA = 3 then 'Amarela'
		when CS_RACA = 4 then 'Parda'
		when CS_RACA = 5 then 'Indígena'
		when CS_RACA = 9 then 'Ignorado'
	end as raca_cor,
	list_sort(list_distinct([
		case when AGRAVAIDS = 1 then 'AIDS' else null end,
		case when AGRAVALCOO = 1 then 'Alcoolismo' else null end,
		case when AGRAVDIABE = 1 then 'Diabetes' else null end,
		case when AGRAVDOENC = 1 then 'Doença mental' else null end,
		case when AGRAVDROGA = 1 then 'Uso de drogas ilícitas' else null end,
		case when AGRAVTABAC = 1 then 'Tabagismo' else null end,
		case when AGRAVOUTRA = 1 then AGRAVOUTDE else null end
	])) as comorbidades,
	array_length(comorbidades) as n_comorbidades,
	case
		when TRATAMENTO = 1 then 'Caso Novo'
		when TRATAMENTO = 2 then 'Recidiva'
		when TRATAMENTO = 3 then 'Reingresso após abandono'
		when TRATAMENTO = 4 then 'Não Sabe'
		when TRATAMENTO = 5 then 'Transferência'
		when TRATAMENTO = 6 then 'Pós-óbito'
	end as tipo_entrada,
	list_sort(list_distinct([
		case when POP_LIBER = 1 then 'Privado de liberdade' else null end,
		case when POP_RUA = 1 then 'Situação de rua' else null end,
		case when POP_SAUDE = 1 then 'Profissional de Saúde' else null end,
		case when POP_IMIG = 1 then 'Imigrante' else null end,
		case when BENEF_GOV = 1 then 'Beneficiário programa de transferência de renda' else null end
	])) as populacao_especial,
	case
		when FORMA = 1 then 'Pulmonar'
		when FORMA = 2 then 'Extrapulmonar'
		when FORMA = 3 then 'Pulmonar + Extrapulmonar'
	end as forma,
	case
		when SITUA_ENCE = 1  then 'Cura'
		when SITUA_ENCE = 2  then 'Abandono'
		when SITUA_ENCE = 3  then 'Óbito por TB'
		when SITUA_ENCE = 4  then 'Óbito por outras causas'
		when SITUA_ENCE = 5  then 'Transferência'
		when SITUA_ENCE = 6  then 'Mudança de diagnóstico'
		when SITUA_ENCE = 7  then 'TB-DR'
		when SITUA_ENCE = 8  then 'Mudança de esquema'
		when SITUA_ENCE = 9  then 'Falência'
		when SITUA_ENCE = 10 then 'Abandono primário'
	end as desfecho,
	ADDRESS_CORE as endereco,
	endereco_cnefe as endereco_cnefe,
	nm_bairro as bairro,
	case
		when (NM_LOGRADO is null OR NM_LOGRADO = '') and (NM_COMPLEM is null or NM_COMPLEM = '') then 0
		when (regexp_matches(NM_LOGRADO, '\bSITUACAO\b', 'i')
		   or regexp_matches(NM_LOGRADO, '\bMORADOR\b', 'i')
		   or regexp_matches(NM_LOGRADO, '\bDE RUA\b', 'i')
		   or regexp_matches(NM_LOGRADO, '\bSEM ENDERECO\b', 'i')) then 0
		else 1
	end as georreferenciado,
	LATITUDE  AS lat,
	LONGITUDE AS long
	from tb_sinan
);")

DBI::dbDisconnect(con_duck, shutdown = TRUE)

# Verificação rápida
con_check <- DBI::dbConnect(duckdb::duckdb(), "local/sinan.duckdb", read_only = TRUE)
DBI::dbGetQuery(con_check, "SELECT COUNT(*) as total FROM tb_sinan_treated")
DBI::dbGetQuery(con_check, "SELECT COUNT(*) as com_coords FROM tb_sinan_treated WHERE lat IS NOT NULL AND long IS NOT NULL")
DBI::dbDisconnect(con_check, shutdown = TRUE)
