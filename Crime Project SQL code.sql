-- IMPORT OLDER POLICE STREET DATA



--//////////////// CREATES CLEAN London Street Table \\\\\\\\\\\\\\\\\\\
--////////////////////////////// \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
if object_id('[dbo].[1610CleanLondonStreet]') is not null
drop table [dbo].[1610CleanLondonStreet] 
go

select --Creating clean Street data for London police only
[Month]
,[Reported by]
,[Falls within]
,[Longitude]
,[Latitude]
,[Location]
,case when [Crime type] LIKE '%Hillingdon%' THEN [Last outcome category]
else [Crime type]
end [CleanCrimeType]
,case when [LSOA code] LIKE '%Ickenham%' THEN [LSOA name]
else [LSOA code]
end [CleanLSOACode]
,case when [LSOA name] LIKE '%E0100%' THEN [Crime type]
else [LSOA name]
end [CleanLSOAName]
into [dbo].[1610CleanLondonStreet]
from [dbo].[AllMetStreetRaw1610]
where [Latitude] <> ''  --Drops rows with no exact location data
order by [Month]

Alter table [dbo].[1610CleanLondonStreet] -- Create new CrimeID that is more lean than the existing one. Also gives an ID to every crime
Add NewCrimeID int identity(1,1)

alter table [dbo].[1610CleanLondonStreet] --Uses last election results data for each year.
	add ElecYr char(4)

update [dbo].[1610CleanLondonStreet]
	set ElecYr = '2010' 
		where left([Month],4) between 2010 and 2014
update [dbo].[1610CleanLondonStreet]
	set ElecYr = '2015'
		where left([Month],4) between 2015 and 2016
update [dbo].[1610CleanLondonStreet]
	set ElecYr = '2017'
		where left([Month],4) between 2017 and 2018


if object_id('[dbo].[CleanLondonStreet]') is not null
drop table [dbo].[CleanLondonStreet]
go

SELECT 
	isnull([NewCrimeID], '0') as [CrimeID]
,[Month]
,[Reported by]
,[Falls within]
,[Longitude]
,[Latitude]
,[Location]
,[CleanCrimeType] as [Crime Type]
,[CleanLSOACode] as [LSOA Code]
,[CleanLSOAName] as [LSOA Name]
,[ElecYr]
,case
when left([Month],4) = '2010' THEN '2010'
when left([Month],4) = '2011' THEN '2011'
when left([Month],4) = '2012' THEN '2012'
when left([Month],4) = '2013' THEN '2013'
when left([Month],4) = '2014' THEN '2014'
when left([Month],4) = '2015' THEN '2015'
when left([Month],4) in ('2016', '2017', '2018') THEN '2016'
else '0'
end as [LSOAPopYr]--This is needed because LSOA pop data is not available for 17/18
	into [dbo].[CleanLondonStreet]
  FROM [dbo].[1610CleanLondonStreet]
GO


--///////////// CREATE TABLE LSOA CONSTITUENCIES \\\\\\\\\\\\\\\\\\\\\\
--///// THIS CONVERTS LSOA ---> Pol Constituency  from ALTERYX \\\\\\\\\

--Initially used Alteryx to intersect two shape files and return all collumn values
--as well as the overlap area.

--Here I then use a CTE to only extract the rows with the greatest overlap.
--This ensures that for any given LSOA chosen, it only corresponds to a single political constituency,
--the one in which it has the most area in. 

if object_id('[LSOA].[LSOAConstituencies]') is not null
drop table [LSOA].[LSOAConstituencies]
go

with cte --Creates table linking LSOA to Voting Constituency
as
(
select 
[LSOA11CD]
,[LSOA11NM]
,replace([NAME], 'Boro Const', '') as [Voting Constituency]
,[LAD11CD]
,[LAD11NM]
,[MSOA11CD]
,[MSOA11NM]
,[RGN11NM]
,[AREA_CODE]
,[HECTARES]
,[AVHHOLDSZ]
,[HHOLDS]
,[POPDEN]
,[AreaSqKm]
,rank() over (partition by [LSOA11NM] order by [AreaSqKm] desc) OverlapRank
from [dbo].[lsoa_constituency_overlap]
)
select 
*
into [LSOA].[LSOAConstituencies]
from cte
where OverlapRank = 1



if object_id ('[star].[LSOAConstituencies]') is not null
drop table [star].[LSOAConstituencies]
go

SELECT 
	isnull([LSOA11CD], 'Unknown') [LSOAID]
      ,[LSOA11NM]
      ,replace([Voting Constituency], 'Holborn and St. Pancras', 'Holborn and St Pancras') [Voting Constituency]
      ,[LAD11CD]
      ,[LAD11NM]
      ,[MSOA11CD]
      ,[MSOA11NM]
      ,[RGN11NM]
      ,[AREA_CODE]
      ,[HECTARES]
      ,[AVHHOLDSZ]
      ,[HHOLDS]
      ,[POPDEN]
      ,[AreaSqKm]
      ,[OverlapRank]
	  into [star].[LSOAConstituencies]
  FROM [LSOA].[LSOAConstituencies]
GO

--///////// PIVOT Election Results \\\\\\\\\\\\\\\
--/////////////////////\\\\\\\\\\\\\\\\\\\\\\\\\

if object_id('[political].[ElecResultsPivoted]') is not null
drop table [political].[ElecResultsPivoted]
go

select 
*
into [political].[ElecResultsPivoted]
from (
select
[Year] as [Year]
,[Code] as [Code]
,[Constituency] as [Constituency]
,[Region] as [Region]
,[Party] as PartyVotes
,[Candidate Votes]
from [political].[ParliamentElecResultsRaw]) c
pivot(
sum([Candidate Votes]) for PartyVotes in ([Conservative], [Labour], [Lib Dem], [UKIP] )
) p order by [Year] asc, [Constituency] asc


-- //////////CREATE ELECTION DATA TABLE FOR DIMENSIONAL MODEL \\\\\\\\\\\\
--/////////////////////////////////\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\

if object_id('star.ElectionDim') is not null
drop table star.ElectionDim
go

select
isnull(cast(erp.[Year] as varchar) +cast(erp.[Code] as varchar), 'Unknown') as [ElectionID]
,erp.[Year]
,erp.[Code]
,erp.[Constituency]
,erp.[Region]
,er.[Majority Party]
,er.[Majority]
,er.[Majority %] * 100 as [Majority%]
,er.[Total constituency votes]
,isnull(erp.[Conservative],0) [Conservative]
,isnull(erp.[Labour], 0) [Labour]
,isnull(erp.[Lib Dem], 0) [Lib Dem]
,isnull(erp.[UKIP], 0) [UKIP]
,isnull(erp.[Green], 0) [Green]
,isnull(erp.[Plaid Cymru], 0) [Plaid Cymru]
,isnull(round((erp.[Conservative] / er.[Total constituency votes]) * 100, 2),0) as [Con%]
,isnull(round((erp.[Labour] / er.[Total constituency votes]) * 100, 2),0) as [Lab%]
,isnull(round((erp.[Lib Dem] /	er.[Total constituency votes]) * 100,2),0) as [LD%]
,isnull(round((erp.[UKIP] /er.[Total constituency votes]) * 100,2),0) as [UKIP%]
into star.ElectionDim
from [political].[ElecResultsPivoted] erp
	inner join [political].[ParliamentElecResultsRaw] er
	on erp.Code = er.Code	
		and erp.Year = er.[Year]
	where er.[Majority %] is not null




--////////////// LSOA Population Data cleansing and joining \\\\\\\\\\\\\
--//////////////////////////                        \\\\\\\\\\\\\\\\\\\\\\

--I used this to bin the raw LSOA data which was split by individual age years
--Rather than repeating the code multiple times, i just changed the table name.
select
[Area Codes]
,[LSOA]
,[All Ages] as [All Ages]
,[0]+[1]+[2]+[3]+[4] as [0-4]
,[5]+[6]+[7]+[8]+[9] as [5-9]
,[10]+[11]+[12]+[13]+[14] as [10-14]
,[15]+[16]+[17]+[18]+[19] as [15-19]
,[20]+[21]+[22]+[23]+[24] as [20-24]
,[25]+[26]+[27]+[28]+[29] as [25-29]
,[30]+[31]+[32]+[33]+[34] as [30-34]
,[35]+[36]+[37]+[38]+[39] as [35-39]
,[40]+[41]+[42]+[43]+[44] as [40-44]
,[45]+[46]+[47]+[48]+[49] as [45-49]
,[50]+[51]+[52]+[53]+[54] as [50-54]
,[55]+[56]+[57]+[58]+[59] as [55-59]
,[60]+[61]+[62]+[63]+[64] as [60-64]
,[65]+[66]+[67]+[68]+[69] as [65-69]
,[70]+[71]+[72]+[73]+[74] as [70-74]
,[75]+[76]+[77]+[78]+[79] as [75-79]
,[80]+[81]+[82]+[83]+[84] as [80-84]
,[85]+[86]+[87]+[88]+[89] as [85-89]
,[90+] as [90+]
into [LSOA].[2015Binned]
from [LSOA].[2015RawPop]
where [Area Names] IS NULL

if object_id('LSOA.2011Binned') IS NOT NULL
drop table [LSOA].[2011Binned]
go
select
[Area Codes]
,[F3] as [LSOA]
,[All Ages]
,[0-4]
,[5-9]
,[10-14]
,[15-19]
,[20-24]
,[25-29]
,[30-34]
,[35-39]
,[40-44]
,[45-49]
,[50-54]
,[55-59]
,[60-64]
,[65-69]
,[70-74]
,[75-79]
,[80-84]
,[85-89]
,[90+]
into [LSOA].[2011Binned]
from [LSOA].[2011RawPop]
where [Area Names] IS NULL

--Tagging each aggregated table with the year that it was from. 

if object_id('[LSOA].[2010TaggedPop]') is not null
drop table [LSOA].[2010TaggedPop]
go
select -- The raw 2010 data didn't have the end part of the LSOA name. Had to get this from a different table and match by code. 
lpop.[Area Codes]
,lc.[LSOA11NM] as [LSOA]
,lpop.[All Ages]
,lpop.[0-4]
,lpop.[5-9]
,lpop.[10-14]
,lpop.[15-19]
,lpop.[20-24]
,lpop.[25-29]
,lpop.[30-34]
,lpop.[35-39]
,lpop.[40-44]
,lpop.[45-49]
,lpop.[50-54]
,lpop.[55-59]
,lpop.[60-64]
,lpop.[65-69]
,lpop.[70-74]
,lpop.[75-79]
,lpop.[80-84]
,lpop.[85-89]
,lpop.[90+]
,'2010' as [LSOAPopYr]
into [LSOA].[2010TaggedPop]
from [LSOA].[2010Binned] lpop
inner join star.LSOAConstituencies lc 
on lpop.[Area Codes] = lc.LSOAID

if object_id('[LSOA].[2011TaggedPop]') is not null
drop table [LSOA].[2011TaggedPop]
go
select 
lpop.*
,'2011' as [LSOAPopYr]
into [LSOA].[2011TaggedPop]
from [LSOA].[2011Binned] lpop
inner join star.LSOAConstituencies lc --Joining to a known table of london LSOAs filters out all LSOAs outside of London
on lpop.[Area Codes] = lc.LSOAID

if object_id('[LSOA].[2012aggedPop]') is not null
drop table [LSOA].[2012TaggedPop]
go
select 
lpop.*
,'2012' as [LSOAPopYr]
into [LSOA].[2012TaggedPop]
from [LSOA].[2012Binned] lpop
inner join star.LSOAConstituencies lc 
on lpop.[Area Codes] = lc.LSOAID

if object_id('[LSOA].[2013TaggedPop]') is not null
drop table [LSOA].[2013TaggedPop]
go
select 
lpop.*
,'2013' as [LSOAPopYr]
into [LSOA].[2013TaggedPop]
from [LSOA].[2013Binned] lpop
inner join star.LSOAConstituencies lc 
on lpop.[Area Codes] = lc.LSOAID

if object_id('[LSOA].[2014TaggedPop]') is not null
drop table [LSOA].[2014TaggedPop]
go
select 
lpop.*
,'2014' as [LSOAPopYr]
into [LSOA].[2014TaggedPop]
from [LSOA].[2014Binned] lpop
inner join star.LSOAConstituencies lc 
on lpop.[Area Codes] = lc.LSOAID

if object_id('[LSOA].[2015TaggedPop]') is not null
drop table [LSOA].[2015TaggedPop]
go
select 
lpop.*
,'2015' as [LSOAPopYr]
into [LSOA].[2015TaggedPop]
from [LSOA].[2015Binned] lpop
inner join star.LSOAConstituencies lc 
on lpop.[Area Codes] = lc.LSOAID

select
lpop.*
,'2016' as [LSOAPopYr]
into [LSOA].[2016TaggedPop]
from [LSOA].[2016Binned] lpop
inner join star.LSOAConstituencies lc 
on lpop.[Area Codes] = lc.LSOAID


if object_id('LSOA.CombinedPop') is not null
drop table LSOA.CombinedPop
go

select --Joining all the binned LSOA data for years 2010-2016
*
into LSOA.CombinedPop
 from [LSOA].[2010TaggedPop]
UNION ALL
select
* from [LSOA].[2011TaggedPop]
UNION ALL
select
* from [LSOA].[2012TaggedPop]
UNION ALL
select
* from [LSOA].[2013TaggedPop]
UNION ALL
select
* from [LSOA].[2014TaggedPop]
UNION ALL
select
* from [LSOA].[2015TaggedPop]
UNION ALL
select
* from [LSOA].[2016TaggedPop]

--/////////// Create Dimension for LSOA Population for each year \\\\\\\\\\\\
--//////////////////////////////// \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\

if object_id('[star].[LSOAPop]') is not null
drop table [star].[LSOAPop]
go
SELECT 
isnull(cast([LSOAPopYr] + [Area Codes] as nchar(13)), 'Unknown') as [LSOAPopID] 
,[Area Codes]
,[LSOA]
,[All Ages]
,[0-4]
,[5-9]
,[10-14]
,[15-19]
,[20-24]
,[25-29]
,[30-34]
,[35-39]
,[40-44]
,[45-49]
,[50-54]
,[55-59]
,[60-64]
,[65-69]
,[70-74]
,[75-79]
,[80-84]
,[85-89]
,[90+]
,[LSOAPopYr]
	  into star.LSOAPop
  FROM [LSOA].[CombinedPop]


  --////////////// CREATES LSOA DEPRIVATION TABLE \\\\\\\\\\\\\\\\\\\\
--////////////////                              \\\\\\\\\\\\\\\\\\\\
if object_id('[star].[Deprivation]') is not null
drop table [star].[Deprivation]
go

SELECT 
	  isnull(cast([Reference area] as nvarchar(40)), 'Unknown') as [LSOAName] --LSOA Code
      ,isnull(cast(lc.LSOAID as nchar(9)), 'unknown') as [LSOAID]
	  ,[a# Index of Multiple Deprivation (IMD)]
      ,[b# Income Deprivation Domain]
      ,[c# Employment Deprivation Domain]
      ,[d# Education, Skills and Training Domain]
      ,[e# Health Deprivation and Disability Domain]
      ,[f# Crime Domain]
      ,[g# Barriers to Housing and Services Domain]
      ,[h# Living Environment Deprivation Domain]
      ,[i# Income Deprivation Affecting Children Index (IDACI)]
      ,[j# Income Deprivation Affecting Older People Index (IDAOPI)]
	  into [star].[Deprivation]
  FROM [LSOA].[Deprivation2] ld
inner join star.LSOAConstituencies lc 
on ld.[Reference area] = lc.LSOA11NM
GO



--////////////// CREATE CRIME TYPE DIMENSION\\\\\\\\\\\\\\\\\\\\
--////////////////                              \\\\\\\\\\\\\\\\\\\\

create table CrimeType( 
CrimeTypeID int identity(1,1) not null primary key
,CrimeType varchar(40)
)

Insert into [dbo].[CrimeType] (CrimeType) 
select distinct
[CleanCrimeType]
from [dbo].[1610CleanLondonStreet]


--//////////////////  Create FACT TABLE \\\\\\\\\\\\\\\\\\\\\\\\\\
--/////////////////////////////\\\\\\\\\//////////////////////////

if object_id ('star.FACT') is not null
drop table star.FACT
go
select 
ls.CrimeID as [CrimeID]
,ls.[Month] as [Month]
,ls.Longitude as [Longitude]
,ls.Latitude as [Latitude]
,ls.Location
,lc.LSOAID as [LSOAID]
,ct.CrimeTypeID as [CrimeTypeID]
,ed.ElectionID as [ElectionID]
,lsd.[LSOAID] as [DeprivationID]
,ls.LSOAPopYr as [LSOAPopYr]
,pop.LSOAPopID as [LSOAPopID]
into star.FACT
from [dbo].[CleanLondonStreet] ls --7965864
inner join [star].[LSOAConstituencies] lc --7957507 -- lose the crime LSOAs not in London
	on ls.[LSOA Code] = lc.LSOAID
inner join [star].[CrimeType] ct --7957507
	on ls.[Crime Type] = ct.CrimeType
inner join [star].[Deprivation] lsd --7957507
	on ls.[LSOA Code] = lsd.[LSOAID]
inner join [star].[ElectionDim] ed --7957507
	on ls.ElecYr = ed.[Year]
	AND lc.[Voting Constituency] = ed.Constituency
inner join [star].[LSOAPop] pop --7957507
	on lc.[LSOAID] = pop.[Area Codes]
	and ls.LSOAPopYr = pop.LSOAPopYr



--///////////////////////////////////////////
--/////////////////////////////////////////////


alter table [star].[Deprivation] 
add primary key ([LSOAID])

alter table [star].[ElectionDim]
add primary key ([ElectionID])

alter table [star].[LSOAConstituencies]
add primary key ([LSOAID])

alter table [star].[LSOAPop]
add primary key ([LSOAPopID])

alter table [star].[CrimeType]
add primary key ([CrimeTypeID])

alter table star.fact 
add constraint FK_CrimeType foreign key (CrimeTypeID)
	references [star].[CrimeType] (CrimeTypeID)

alter table star.fact 
add constraint FK_LSOAID foreign key (LSOAID)
	references [star].[LSOAConstituencies] (LSOAID)

alter table star.fact 
add constraint FK_ElectionID foreign key (ElectionID)
	references [star].[ElectionDim] (ElectionID)

alter table [star].[fact]
	add constraint FK_DepID foreign key ([LSOAID])
		references [star].[Deprivation]  ([LSOAID])

alter table star.fact 
add constraint FK_LSOAPopID foreign key ([LSOAPopID])
	references [star].[LSOAPop] ([LSOAPopID])




--//////////// GENERATES POPULATION IN EACH CONSTITUENCY FOR EACH YEAR \\\\\\\\\
-- ////////////////////////////////        \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\

create schema derived 


if object_id('derived.ConPop') is not null
drop table derived.ConPop
go
	with cte as(  -- 
select distinct
ed.constituency 
,lc.LSOA11NM
,pop.[All Ages]
,pop.[0-4]
,pop.[5-9]
,pop.[10-14]
,pop.[15-19]
,pop.[20-24]
,pop.[25-29]
,pop.[30-34]
,pop.[35-39]
,pop.[40-44]
,pop.[45-49]
,pop.[50-54]
,pop.[55-59]
,pop.[60-64]
,pop.[65-69]
,pop.[70-74]
,pop.[75-79]
,pop.[80-84]
,pop.[85-89]
,pop.[90+]
,pop.LSOAPopYr as [LSOAPopYr]
,ed.[Code]
from star.fact f
inner join [star].[LSOAConstituencies] lc
	on f.[LSOAID] = lc.LSOAID
inner join [star].[CrimeType] ct
	on f.[CrimeTypeID] = ct.CrimeTypeID
inner join [star].[Deprivation] lsd
	on f.DeprivationID = lsd.[DeprivationID]
inner join [star].[ElectionDim] ed
	on f.ElectionID = ed.ElectionID
inner join [star].[LSOAPop] pop
	on f.LSOAPopID = pop.LSOAPopID
	)

select distinct
[Constituency]
,[PopYr] + 
,[Code]
,[LSOAPopYr] as [PopYr]
,sum([All Ages]) over (partition by [Constituency],[LSOAPopYr]) ConPopByYr
,sum([0-4]) over (partition by [Constituency],[LSOAPopYr])   as [Con 0-4] 
,sum([5-9]) over (partition by [Constituency],[LSOAPopYr])   as [Con 5-9]
,sum([10-14]) over (partition by [Constituency],[LSOAPopYr]) as [Con 10-14]
,sum([15-19]) over (partition by [Constituency],[LSOAPopYr]) as [Con 15-19]
,sum([20-24]) over (partition by [Constituency],[LSOAPopYr]) as [Con 20-24]
,sum([25-29]) over (partition by [Constituency],[LSOAPopYr]) as [Con 25-29]
,sum([30-34]) over (partition by [Constituency],[LSOAPopYr]) as [Con 30-34]
,sum([35-39]) over (partition by [Constituency],[LSOAPopYr]) as [Con 35-39]
,sum([40-44]) over (partition by [Constituency],[LSOAPopYr]) as [Con 40-44]
,sum([45-49]) over (partition by [Constituency],[LSOAPopYr]) as [Con 45-49]
,sum([50-54]) over (partition by [Constituency],[LSOAPopYr]) as [Con 50-54]
,sum([55-59]) over (partition by [Constituency],[LSOAPopYr]) as [Con 55-59]
,sum([60-64]) over (partition by [Constituency],[LSOAPopYr]) as [Con 60-64]
,sum([65-69]) over (partition by [Constituency],[LSOAPopYr]) as [Con 65-69]
,sum([70-74]) over (partition by [Constituency],[LSOAPopYr]) as [Con 70-74]
,sum([75-79]) over (partition by [Constituency],[LSOAPopYr]) as [Con 75-79]
,sum([80-84]) over (partition by [Constituency],[LSOAPopYr]) as [Con 80-84]
,sum([85-89]) over (partition by [Constituency],[LSOAPopYr]) as [Con 85-89]
,sum([90+]) over (partition by [Constituency],[LSOAPopYr])   as [Con 90+] 
into derived.ConPop
from cte


-- /////// Creating View that will be used in Tableau \\\\\\\\\\\\\\\\\
-- ////////////////////////////			 \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\


if object_id('ConstituencyCrimeCountByType') is not null
drop view ConstituencyCrimeRateByType
go

create view ConstituencyCrimeCountByType as
	
select distinct 
ed.[Constituency]
,ed.Code as [Code]
,f.CrimeTypeID as [CrimeTypeID]
,ct.CrimeType as [CrimeType]
,left(f.[Month], 4) as [Year]
,cp.ConPopByYr as [ConPopByYr]
,cp.[Con 0-4] 
,cp.[Con 5-9]
,cp.[Con 10-14]
,cp.[Con 15-19]
,cp.[Con 20-24]
,cp.[Con 25-29]
,cp.[Con 30-34]
,cp.[Con 35-39]
,cp.[Con 40-44]
,cp.[Con 45-49]
,cp.[Con 50-54]
,cp.[Con 55-59]
,cp.[Con 60-64]
,cp.[Con 65-69]
,cp.[Con 70-74]
,cp.[Con 75-79]
,cp.[Con 80-84]
,cp.[Con 85-89]
,cp.[Con 90+] 
,count(f.CrimeID) over (partition by ed.Code, left(f.[Month], 4)) as [TotalCrimeCount]
,count(f.CrimeID) over (partition by ed.Code, left(f.[Month], 4), f.CrimeTypeID) as [CrimeCountPerType]
,ed.[Year] as [ElecYr]
,ed.[Con%] as [Con%]
,ed.Conservative as [Conservative]
,ed.[Lab%] as [Lab%]
,ed.Labour as [Lab]
,ed.[LD%] as [LD%]
,ed.[Lib Dem] as [Lib Dem]
,ed.[UKIP%] as [UKIP%]
,ed.UKIP as [UKIP]
,ed.[Majority Party] as [Majority Party]
,ed.[Majority%] as [Majority%]
,ed.[Total constituency votes] as [Total constituency votes]
from star.fact f
inner join [star].[LSOAConstituencies] lc
	on f.[LSOAID] = lc.LSOAID
inner join [star].[CrimeType] ct
	on f.[CrimeTypeID] = ct.CrimeTypeID
inner join [star].[Deprivation] lsd
	on f.DeprivationID = lsd.[DeprivationID]
inner join [star].[ElectionDim] ed
	on f.ElectionID = ed.ElectionID
inner join [star].[LSOAPop] pop
	on f.LSOAPopID = pop.LSOAPopID
inner join derived.ConPop cp
	on f.LSOAPopYr = cp.PopYr
	and lc.[Voting Constituency] = cp.Constituency




