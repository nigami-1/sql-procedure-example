ALTER PROCEDURE [dbo].[IssuedFin_Per]
	@i_BranchId				name,
    	@i_ClientId				code,
	@i_ContractId				code = null,
	@i_sDt					dt,
    	@i_eDt					dt,
	@ErrInfo				maxText = null OUTPUT
AS
BEGIN
	SET NOCOUNT ON;

	if @i_BranchId = '' set @i_BranchId = null 
	if @i_ClientId = '' set @i_ClientId = null

	SELECT CONVERT(VARCHAR,CONVERT(datetime,@i_sDt),104) AS sDt
		 , CONVERT(VARCHAR,CONVERT(datetime,@i_eDt),104) AS eDt
		 , CONVERT(VARCHAR,dbo.OnlyDate(GetDate()),104) AS DtCurr
		 , D.ClientFullName 
		 , D.ClientExtCode
		 , D.GenContractNum
		 , D.InvoiceAmount
		 , D.InvoiceCode
		 , D.InvoiceDate
		
		 , convert (numeric(28,12), MAX(D.Comm1Value)) AS Comm1Value
		 , convert (numeric(28,2), SUM(D.Comm1NoneVatAmount)) AS Comm1NoneVatAmount
		 , convert (numeric(28,2), SUM(D.Comm1VatAmount)) AS Comm1VatAmount

		 , convert (numeric(28,12), MAX(D.Comm2Value)) AS Comm2Value
		 , convert (numeric(28,2), SUM(D.Comm2NoneVatAmount)) AS Comm2NoneVatAmount
		 , convert (numeric(28,2), SUM(D.Comm2VatAmount)) AS Comm2VatAmount
		 , convert (numeric(28,2), SUM(D.Comm2Multy)) AS Comm2Multy
		 , convert (numeric(28,2), MAX(D.Comm2Base)) AS Comm2Base

		 , D.TranshId
		 , convert (numeric(28,12), MAX(D.Comm3Value)) AS Comm3Value
		 , convert (numeric(28,2), SUM(D.Comm3NoneVatAmount)) AS Comm3NoneVatAmount
		 , convert (numeric(28,2), SUM(D.Comm3VatAmount)) AS Comm3VatAmount
		 , convert (numeric(28,2), MAX(D.Comm3Multy)) AS Comm3Multy
		 , convert (numeric(28,2), MAX(D.Comm3Base)) AS Comm3Base
		 , convert (numeric(28,12), MAX(D.Comm3ReCalc)) AS Comm3ReCalc

		 , D.ManagerInvolvementDep
		 , D.ManagerInvolvementFIO
		 , D.ManagerSupport
		 , D.GRP
		 , D.ValCode
		 ,D.ClientINN 
		 ,D.ContractNum 
		 ,D.ContractDate 
		 ,D.FactContractNum
		 ,D.FactContractDate,
			d.DelayTypeId as DelayTypeId,
			d.DelayDays as DelayDays
	FROM(
	SELECT CASE WHEN Cl.PersonTypeId='Физическое лицо' or Cl.OrgFormId Is NULL THEN Cl.ShortName ELSE Cl.OrgFormId+' '+CHAR(171)+Cl.ShortName+CHAR(187) END as ClientFullName
		 , exCl.ExtCode AS ClientExtCode
		 , G.ContractNum AS GenContractNum
		 , S.InvoiceCode AS InvoiceCode
		 , S.SuppAmount AS InvoiceAmount
		 , S.SupplyDate AS InvoiceDate
		 , case when count(O.TranshId) over (partition by s.supplyId) > 1 then O.TranshId else null end as TranshId
		 , O.OperDate
		 , O.VCalc
		 , O.FCalc
		 , CASE WHEN Di.Name = 'Коррекция' THEN 1 ELSE 0 END AS GRP
		 , CASE WHEN O.CommissionTypeId like 'Комиссия 1%' THEN ISNULL(CONVERT(numeric(28,12),dbo.getSubValue('Ставка',O.FCalc,O.VCalc)),0) ELSE 0 END AS Comm1Value
		 , CASE WHEN O.CommissionTypeId like 'Комиссия 1%' THEN ISNULL(O.NoneVatAmount,0) ELSE 0 END AS Comm1NoneVatAmount
		 , CASE WHEN O.CommissionTypeId like 'Комиссия 1%' THEN ISNULL(O.VatAmount,0) ELSE 0 END AS Comm1VatAmount
		 , CASE WHEN O.CommissionTypeId like 'Комиссия 2%' THEN ISNULL(CONVERT(numeric(28,12),dbo.getSubValue('Ставка',O.FCalc,O.VCalc)),0) ELSE 0 END AS Comm2Value
		 , CASE WHEN O.CommissionTypeId like 'Комиссия 2%' THEN ISNULL(O.NoneVatAmount,0) ELSE 0 END AS Comm2NoneVatAmount
		 , CASE WHEN O.CommissionTypeId like 'Комиссия 2%' THEN ISNULL(O.VatAmount,0) ELSE 0 END AS Comm2VatAmount
		 , CASE WHEN O.CommissionTypeId like 'Комиссия 2%' THEN ISNULL(CONVERT(numeric(28,0),dbo.getSubValue('Показатель',O.FCalc,O.VCalc)),0) ELSE 0 END AS Comm2Multy
		 , CASE WHEN O.CommissionTypeId like 'Комиссия 2%' THEN ISNULL(CONVERT(numeric(28,12),dbo.getSubValue('База',O.FCalc,O.VCalc)),0) ELSE 0 END AS Comm2Base
		 , CASE WHEN O.CommissionTypeId like 'Комиссия 3%' THEN ISNULL(CONVERT(numeric(28,12),dbo.getSubValue('Ставка',O.FCalc,O.VCalc)),0) ELSE 0 END AS Comm3Value
		 , CASE WHEN O.CommissionTypeId like 'Комиссия 3%' THEN ISNULL(O.NoneVatAmount,0) ELSE 0 END AS Comm3NoneVatAmount
		 , CASE WHEN O.CommissionTypeId like 'Комиссия 3%' THEN ISNULL(O.VatAmount,0) ELSE 0 END AS Comm3VatAmount
		 , CASE WHEN O.CommissionTypeId like 'Комиссия 3%' THEN ISNULL(CONVERT(numeric(28,0),dbo.getSubValue('Показатель',O.FCalc,O.VCalc)),0) ELSE 0 END AS Comm3Multy
		 , CASE WHEN O.CommissionTypeId like 'Комиссия 3%' THEN ISNULL(CONVERT(numeric(28,12),dbo.getSubValue('База',O.FCalc,O.VCalc)),0) ELSE 0 END AS Comm3Base
		 , CASE WHEN O.CommissionTypeId like 'Комиссия 3%' THEN ISNULL(CONVERT(numeric(28,12),dbo.getSubValue('Пересчет по новой ставке',O.FCalc,O.VCalc)),0) ELSE 0 END AS Comm3ReCalc
		 , Dp.DepName AS ManagerInvolvementDep
		 , E.EmplFIO AS ManagerInvolvementFIO
		 , dbo.GetContractorServiceList(CDL.ClientId,@i_eDt) As ManagerSupport
		 , S.ValCode AS ValCode
		 ,Inf.ClientINN 
		 ,Inf.ContractNum 
		 ,Inf.ContractDate
		 ,Inf.FactContractNum
		 ,Inf.FactContractDate	,
		 s.DelayTypeId as DelayTypeId,
		 s.PaymDelay as DelayDays	  
	   FROM Supplies S WITH(NOLOCK)
	   JOIN Operations O ON O.SupplyId = S.SupplyId AND O.IsSummary = 0
	   JOIN ComissionTypes Ct WITH(NOLOCK) ON Ct.CommissionTypeId = O.CommissionTypeId
		AND Ct.AddOper = O.OperationTypeId
	   JOIN ClientDebtorLink CDL WITH(NOLOCK) ON CDL.ClientDebtorLinkId = S.ClientDebtorLinkId
	   JOIN ClientModels Cm WITH(NOLOCK) ON Cm.ClientModelId = CDL.ClientModelId
	   JOIN Contracts G WITH(NOLOCK) ON G.ContractId = Cm.ContractId
	   JOIN Contracts cs WITH(NOLOCK) ON cs.ContractId = Cdl.ContractId
	   JOIN Contractors Cl WITH(NOLOCK) ON Cl.ContractorId = CDL.ClientId
	   JOIN Contractors Db WITH(NOLOCK) ON Db.ContractorId = CDL.DebtorId
	   LEFT JOIN Dims Di WITH(NOLOCK) ON Di.DimId = O.DimId
	   LEFT JOIN ExtCodes exCl WITH(NOLOCK) ON exCl.ObjId = 'Контрагент' AND exCl.ObjUK = CDL.ClientId AND exCl.ExtSysId = 'НБС'
	   LEFT JOIN ExtCodes exDb WITH(NOLOCK) ON exDb.ObjId = 'Контрагент' AND exDb.ObjUK = CDL.DebtorId AND exDb.ExtSysId = 'НБС'
	   LEFT JOIN Empls E WITH(NOLOCK) ON E.EmplId = Cl.EmplId
	   LEFT JOIN Departments Dp WITH(NOLOCK) ON Dp.DepartmentId = E.DepartmentId
	   outer apply dbo.TGetContractInfo (CDL.ClientDebtorLinkId) Inf
	 WHERE Ct.CommissionTypeId LIKE 'Комиссия%'
	   AND O.OperDate BETWEEN @i_sDt AND @i_eDt
	   AND ( S.BranchId = @i_BranchId OR @i_BranchId IS NULL )
	   AND ( S.ClientId = @i_ClientId OR @i_ClientId IS NULL )
	   AND ( @i_ContractId is null or @i_ContractId = CDL.ContractId or @i_ContractId = Cm.ContractId)

	) AS D
	GROUP BY D.ClientFullName
		 , D.ClientExtCode
		 , D.GenContractNum
		 , D.InvoiceAmount
		 , D.InvoiceCode
		 , D.InvoiceDate
		 , D.ManagerInvolvementDep
		 , D.ManagerInvolvementFIO
		 , D.ManagerSupport
		 , D.OperDate
		 , D.GRP
		 , D.TranshId
		 , D.ValCode
		 ,D.ClientINN
		 ,D.ContractNum
		 ,D.ContractDate
		 ,D.FactContractNum
		 ,D.FactContractDate
		 ,D.DelayTypeId
		 ,D.DelayDays
	ORDER BY D.ClientFullName, D.GenContractNum, D.InvoiceDate, D.InvoiceCode, D.InvoiceAmount, D.OperDate, D.TranshId
END


























































