USE [FactorABB]
GO
ALTER FUNCTION [dbo].[GetNValue]
(
	 @Name				name
	,@TranshId			code
	,@SupplyId			code
	,@CommTypeId		expr
	,@Dt				dt
	,@ClMod				guid	-- Передается в случае тарифов клиента
	,@CDLink			guid	-- Передается в случае тарифов дебитора 
	,@OpId				guid	-- ссылка на конкетный объект начисления
	,@Amount			summa
)
RETURNS numeric(28,12)
AS
BEGIN
	DECLARE  @Res numeric(28,12)
			,@Big numeric(28,12) = 9999999999999999;

	declare 
		@TranshDate dt,
		@OverDelayComDt dt; 

	declare @hist table (
		DateFrom		dt,
		DateTo			dt, 
		Val				summa,
		PeriodNum		int,
		ReservLim		summa,	
		PeriodRowNum	int
	);

	If exists (Select top 1 1 From PeriodSets Ps Where Ps.PeriodSetId = @Name and Ps.IsActive = 1)
		Select top 1  @Res = TP.Period From TPeriodSetCalc(@Name, @TranshId, @SupplyId,@Dt) TP
	ELSE IF @Name IN ('Без базы','Без показателя')
	BEGIN
		SELECT @Res = 1
		RETURN @RES
	END
	ELSE IF @Name in ('Сумма платежа дебитора','Сумма платежа') AND @OpId Is Not NULL
	BEGIN
		SELECT @Res = 
			isnull((Select top 1 Od.OperDocAmount From OperDocs Od Where Od.OperDocId = @OpId),0)
        RETURN @RES
	END 
	ELSE IF @Name = 'Финансирование' AND @TranshId Is Not NULL
	BEGIN
		SELECT @Res = 
			isnull((	select sum(IsNull(o1.operAmount,0)) from OperSets t1 with(nolock)
			              Join Operations o1 (nolock) on o1.OperationTypeId = t1.OperationTypeId 
						 where t1.SetTypeId = 'FD' and t1.Multy = 1 and o1.TranshId = @TranshId 
						   and o1.IsSummary = 0 ),0)
        RETURN @RES
	END 
	ELSE IF @Name = 'Финансирование' AND @TranshId IS NULL AND @SupplyId IS NOT NULL
	BEGIN
		SELECT @Res = 
			isnull((	select sum(IsNull(o1.operAmount,0)) from OperSets t1 with(nolock)
			            join Operations o1 (nolock) on o1.OperationTypeId = t1.OperationTypeId
						where t1.SetTypeId = 'FD' and t1.Multy = 1 and o1.SupplyId = @SupplyId  
							and o1.IsSummary = 0 ),0)
        RETURN @RES
	END
	ELSE IF @Name = 'Задолженность по финансированию'
	BEGIN
        SELECT @Res = 
			isnull((	select sum(IsNull(o1.operAmount*t1.Multy,0)) from OperSets t1 with(nolock)
			            join Operations o1 (nolock) on o1.OperationTypeId = t1.OperationTypeId  
						where t1.SetTypeId = 'FD' and o1.TranshId = @TranshId 
							and o1.IsSummary = 0 and o1.OperDate < @Dt ),0)
        RETURN @RES
	END
	ELSE IF @Name = 'Подтвержденная задолженность по финансированию'
	BEGIN
		select @res = sum(IsNull(o1.operAmount*t1.Multy,0)) 
		from OperSets t1 with(nolock)
			join Operations o1 on o1.TranshId = @TranshId and o1.OperationTypeId = t1.OperationTypeId
			and o1.IsSummary = 0 and o1.OperDate < @Dt  
		where t1.SetTypeId = 'FD'   
		having min(case		when o1.OperationTypeId = 'Финансирование' then o1.BankDate
							when o1.OperationTypeId = 'Удержанное финансирование' then o1.operDate end) < @dt
		
		set @Res = isnull(@res,0)
		RETURN @RES
	END
	ELSE IF @Name = 'Текущая задолженность за финансирование'
	BEGIN
		select @res = sum(IsNull(o1.operAmount*t1.Multy,0)) 
		from OperSets t1 with(nolock)
			join Operations o1 on o1.TranshId = @TranshId and o1.OperationTypeId = t1.OperationTypeId
			and o1.IsSummary = 0 and  ((o1.OperDate <= @Dt  and t1.Multy > 0) or (o1.OperDate < @Dt  and t1.Multy < 0))
		where t1.SetTypeId = 'FD'   
		having min(case		when o1.OperationTypeId = 'Финансирование' then o1.BankDate
							when o1.OperationTypeId = 'Удержанное финансирование' then o1.operDate end) <= @dt
		
		set @Res = isnull(@res,0)
		RETURN @RES
	END
	ELSE IF @Name = 'Задолженность по финансированию по 1 KK'
	BEGIN
		SELECT @Res =
			isnull((	select sum(IsNull(o1.operAmount*t1.Multy,0)) from OperSets t1 with(nolock)
			            join Operations o1 on o1.OperationTypeId = t1.OperationTypeId
						where t1.SetTypeId = 'FD' and o1.TranshId = @TranshId  
							and o1.IsSummary = 0 and o1.OperDate < @Dt ),0)
		RETURN @RES
	END
	ELSE IF @Name = 'Задолженность по финансированию 2 и выше КК'
	BEGIN
		SELECT @Res = 
			isnull((	select sum(IsNull(o1.operAmount*t1.Multy,0)) from OperSets t1 with(nolock)
			            join Operations o1 (nolock) on o1.OperationTypeId = t1.OperationTypeId
						where t1.SetTypeId = 'FD' and o1.TranshId = @TranshId  
							and o1.IsSummary = 0 and o1.OperDate < @Dt ),0)	
		RETURN @RES
	END
	ELSE IF @Name = 'Просроченная задолженность по финансированию'
	BEGIN
		SELECT @Res = 
			isnull((	select sum(IsNull(o1.operAmount*t1.Multy,0)) from OperSets t1 with(nolock)
			            join Operations o1 (nolock) on o1.OperationTypeId = t1.OperationTypeId
						join Transhs tr1 (nolock) on tr1.TranshId = @TranshId
						where t1.SetTypeId = 'FD' and o1.TranshId = @TranshId  
							and o1.IsSummary = 0 and o1.OperDate < @Dt and tr1.EndDate < @Dt),0)
		RETURN @RES
	END
	ELSE IF @Name = 'Просроченная задолженность по возвратам'
	BEGIN
		SELECT @Res = 
			dbo.ReturnDebtAmount(@SupplyId, NULL, @Dt)
		RETURN @RES
	END
	ELSE IF @Name = 'Просроченная задолженность по комиссиям' AND @OpId IS NOT NULL
	BEGIN
		-- рассчитываем дату выноса на просрочку комиссии, которая не включена в счет, по дате регресса
		select top 1 @OverDelayComDt =
			isnull(dbo.AddDays(EDt.MinDt, IsNull(Cm.CountDay4PayOnRegr,0), Cm.PeriodType4PayOnRegr), dbo.GetTranshEnd(s.SupplyId,NULL)) 
		  + sp.InDayOverDelayNextDt
		from Operations O
		join Supplies S on S.SupplyId = O.SupplyId
		join ClientModels Cm on Cm.ClientModelId = s.ClientModelId
		join ComissionTypes Ct on Ct.CommissionTypeId = O.CommissionTypeId
		  and Ct.CommissionReceptOrderId in ('По счету', 'По дате счета', 'По регрессу')
		join SysParameters Sp On 1=1
		cross apply (Select min(T.EndDate) as MinDt
					 From SuppInTransh Sit 
					 join Transhs T on T.TranshId = Sit.TranshId
					 Where Sit.SupplyId = S.SupplyId) EDt
		where O.OperationId = @OpId	

		SELECT @Res = dbo.maxNum(
			IsNull((Select sum(IsNull(O.OperAmount,0)) 
					From Operations O
					join ComissionTypes Ct on Ct.CommissionTypeId = O.CommissionTypeId
					join ClientModels Cm on Cm.ClientModelId = O.ClientModelId 
					Where O.OperationId = @OpId 
					  and O.OperDate <= @Dt
					  and (O.ReceptDate < @Dt -- комиссия при непустой плановой дате погашения выносится на просрочку на следующий день
					    OR O.ReceptDate is null and @OverDelayComDt <= @Dt)), 0)
		   -IsNull((select sum(IsNull(CO.DebitAmount,0)) 
					From Operations O
					join CompareOperations CO on CO.CreditOperationId = @OpId
					Where O.OperationId = @OpId 
					and ( O.ReceptDate < @Dt and CO.RedeemDate < @Dt
					  OR O.ReceptDate is null and @OverDelayComDt <= @Dt and CO.RedeemDate <= @Dt)),0),0)
		RETURN @RES	
	END 
	ELSE IF @Name = 'Просроченная задолженность по комиссиям' AND @OpId IS NULL AND @SupplyId IS NOT NULL
	BEGIN
		-- рассчитываем дату выноса на просрочку комиссий, которые не включены в счет, по дате регресса
		select top 1 @OverDelayComDt =
			isnull(dbo.AddDays(EDt.MinDt, IsNull(Cm.CountDay4PayOnRegr,0), Cm.PeriodType4PayOnRegr), dbo.GetTranshEnd(s.SupplyId,NULL)) 
		  + sp.InDayOverDelayNextDt
		from Supplies s
		join ClientModels Cm on Cm.ClientModelId = s.ClientModelId
		join SysParameters Sp On 1=1
		cross apply (Select min(T.EndDate) as MinDt
					 From SuppInTransh Sit 
					 join Transhs T on T.TranshId = Sit.TranshId
					 Where Sit.SupplyId = s.SupplyId) EDt
		where s.SupplyId = @SupplyId

		SELECT @Res = dbo.maxNum(
			IsNull((Select sum(IsNull(O.OperAmount,0)) 
					From Operations O
					 join ComissionTypes Ct2 on O.OperationTypeId = Ct2.AddOper -- фильтр: операции начисления комиссии
			         join ComissionTypes Ct1 on Ct1.AddOper = Ct2.AddPennyOper  -- фильтр: по комиссии настроена неустойка
					 Where O.SupplyId = @SupplyId
					   and Ct1.CommissionTypeId = @CommTypeId
                       and O.IsSummary = 0 
					   and O.OperDate <= @Dt
                       and O.IsSummary = 0 				   
					   and (O.ReceptDate < @Dt 
					     or O.ReceptDate is null and Ct2.CommissionReceptOrderId in ('По счету', 'По дате счета', 'По регрессу')
						 and @OverDelayComDt <= @Dt)),0)
		   -IsNull((Select sum(IsNull(CO.DebitAmount,0))
					  From Operations O
					  Join ComissionTypes Ct2 on O.OperationTypeId = Ct2.AddOper
					  Join ComissionTypes Ct1 on Ct1.AddOper = Ct2.AddPennyOper
					  Join CompareOperations CO on CO.CreditOperationId = O.OperationId
					  Join Operations O2 on CO.DebitOperationId = O2.OperationId 
				     Where O.SupplyId = @SupplyId
					   and Ct1.CommissionTypeId = @CommTypeId
					   and O.IsSummary = 0 
					   and (O.ReceptDate < @Dt and CO.RedeemDate < @Dt
					      or O.ReceptDate is null and Ct2.CommissionReceptOrderId in ('По счету', 'По дате счета', 'По регрессу')
						  and @OverDelayComDt <= @Dt and CO.RedeemDate <= @Dt)),0), 0)
		RETURN @RES
	END
	ELSE IF @Name = 'Ежедневная просроченная задолженность по комиссии' AND @CommTypeId IS NOT NULL AND @SupplyId IS NOT NULL
	BEGIN
		
		SELECT top 1 @Res = dbo.ComRecalcForRegress (@SupplyId, (CASE WHEN Ct_C.CommissionReceptBaseId like ('%финансир%') THEN 1 ELSE 0 END), Ct_C.CommissionTypeId,@Dt) -- перерасчет комиссии с ежедневным дорасчетом на срок просрочки (после даты оплаты по регрессе)
			From ComissionTypes Ct_P
			Join ComissionTypes Ct_C on Ct_P.AddOper = Ct_C.AddPennyOper
			Where Ct_P.CommissionTypeId = @CommTypeId

		Set @Res = @Res 	
			- IsNull((Select sum(IsNull(CO.DebitAmount,0))
					  From Operations O
					  Join CompareOperations CO on CO.CreditOperationId = O.OperationId
					  Join ComissionTypes Ct_C on O.CommissionTypeId = Ct_C.AddOper
					  Join ComissionTypes Ct_P on Ct_P.AddOper  = Ct_C.AddPennyOper
					  Where Ct_P.CommissionTypeId = @CommTypeId
					    and O.SupplyId = @SupplyId
 						and CO.RedeemDate < @Dt and O.ReceptDate < @Dt ),0)		
		RETURN @RES
	END

	ELSE IF @Name = 'Просроченная задолженность по комиссиям Х Просрочка' AND @OpId IS NOT NULL
	BEGIN
		SELECT @Res = 
			IsNull((Select sum(IsNull(O.OperAmount*convert(Numeric, @Dt - dbo.GVReceptDate(O.OperationId)),0))
					  From Operations O Where O.OperationId = @OpId and O.ReceptDate < @Dt ),0)
			- IsNull((Select sum(IsNull(CO.DebitAmount*convert(Numeric, @Dt - dbo.GVReceptDate(O.OperationId)),0))
					  From Operations O
					  Join CompareOperations CO on CO.CreditOperationId = O.OperationId
					  Where O.OperationId = @OpId 
						and CO.RedeemDate < @Dt and O.ReceptDate < @Dt ),0)		
		RETURN @RES
	END
	ELSE IF @Name = 'Просроченная задолженность по комиссиям Х Просрочка' AND @OpId IS NULL
	BEGIN
		SELECT @Res =
			IsNull((Select sum(IsNull(O.OperAmount*convert(Numeric, @Dt - dbo.GVReceptDate(O.OperationId)),0))
					  From Operations O
				     Where O.ClientModelId = @ClMod
                       and O.OperationTypeId in (Select Ct.AddOper From ComissionTypes Ct
					                               Join ComissionTypes Pen on Pen.AddOper = Ct.AddPennyOper
												   Where Pen.CommissionTypeId = @CommTypeId) 
				       and O.ReceptDate < @Dt 
                       and O.IsSummary = 0 ),0)
		   -IsNull((Select sum(IsNull(CO.DebitAmount*convert(Numeric, @Dt - dbo.GVReceptDate(O.OperationId)),0))
				      From Operations O, CompareOperations CO
				     Where O.ClientModelId = @ClMod
                       and O.OperationTypeId in (Select Ct.AddOper From ComissionTypes Ct
					                               Join ComissionTypes Pen on Pen.AddOper = Ct.AddPennyOper
												   Where Pen.CommissionTypeId = @CommTypeId) 
				       and CO.CreditOperationId = O.OperationId
				       and CO.RedeemDate < @Dt
				       and O.ReceptDate < @Dt 
                       and O.IsSummary = 0 ),0)
		RETURN @RES
	END
	ELSE IF @Name = 'Просроченные комиссии после оплаты денежного требования' AND @OpId IS NOT NULL
	BEGIN
		SELECT @Res = 
			dbo.maxNum(isnull((SELECT sum(isnull(O.OperAmount, 0))
					  FROM Supplies S
						join ComissionTypes Ct_P on Ct_P.CommissionTypeId = @CommTypeId		-- неустойка по комиссиям
						join ComissionTypes Ct_C on Ct_C.AddPennyOper = Ct_P.AddOper		-- комиссии по которым настроена неустойка
						join Operations O on O.SupplyId = S.SupplyId						-- операции по комиссиям поставки (база для неустойки)
							and O.CommissionTypeId = Ct_C.AddOper
					 WHERE S.SupplyId = @SupplyId
						and O.OperationId = @OpId
						and S.FactPaymDate <= @Dt		-- дата погашения дебиторки = дата просрочки комиссии
						and O.OperDate <= @Dt),0)
			- IsNull((Select sum(IsNull(CO.DebitAmount,0))
					  From Operations O
					  Join CompareOperations CO on CO.CreditOperationId = O.OperationId
					  Where O.OperationId = @OpId 
					    and O.OperDate <= @Dt
						and CO.RedeemDate <= @Dt),0), 0)	
		RETURN @RES
	END
	ELSE IF @Name = 'Просроченные комиссии после оплаты денежного требования' AND @OpId IS NULL
	BEGIN
		SELECT @Res = 
			isnull((SELECT sum(isnull(O.OperAmount * Os.Multy, 0))
					  FROM Supplies S
						join ComissionTypes Ct_P on Ct_P.CommissionTypeId = @CommTypeId		-- неустойка по комиссиям
						join ComissionTypes Ct_C on Ct_C.AddPennyOper = Ct_P.AddOper		-- комиссии по которым настроена неустойка
						join Operations O on O.SupplyId = S.SupplyId						-- операции по комиссиям поставки (база для неустойки)
							and O.CommissionTypeId = Ct_C.CommissionTypeId
						join OperSets Os on Os.OperationTypeId = O.OperationTypeId and Os.SetTypeId = 'CD' -- набор операций - задолженность по комиссиям - берем знак операции
					 WHERE S.SupplyId = @SupplyId
						and S.FactPaymDate <= @Dt		-- дата погашения дебиторки = дата просрочки комиссии
						and O.OperDate <= @Dt),0)
		RETURN @RES
	END
	ELSE IF @Name = 'Накладная как сумма'
	BEGIN
		SELECT @Res = 
			(Select Top 1 Su.InvoiceAmount
               From Supplies Su
              Where Su.SupplyId = @SupplyId
				and Su.SupplyType in ('Поставка','Будущее требование','Поручение')
				and exists (Select top 1 '*' From Operations Op Where Op.SupplyId = Su.SupplyId and Op.OperationTypeId in (select operSetsLoc.OperationTypeId from OperSets operSetsLoc where operSetsLoc.SetTypeId = 'RS')
                               and Op.IsSummary=0 and Op.OperDate <= @Dt)) 
		RETURN @RES
	END
	ELSE IF @Name = 'Сумма профинансированной накладной'
	BEGIN
		SELECT @Res = 
			(SELECT TOP 1 Su.InvoiceAmount 
	           FROM Supplies Su 
	          WHERE Su.SupplyId = @SupplyId
	            AND EXISTS (Select top 1 '*' From Transhs Tr
				              Join SuppInTransh Sit on Tr.TranshId=Sit.TranshId
							  Where Sit.SupplyId=Su.SupplyId
	                           and Tr.TranshDate <= @Dt))
		RETURN @RES
	END
	ELSE IF @Name = 'Сумма накладной с задолженностью за финансирование'
	BEGIN
		SELECT @Res = case when sum(IsNull(o.operAmount*t.Multy,0)) > 0 then max(Su.InvoiceAmount) else 0 end
	        FROM Supplies Su (nolock)
			JOIN Operations o (nolock) on o.SupplyId = Su.SupplyId and o.IsSummary = 0 and o.OperDate < @dt
			JOIN OperSets t with(nolock) on t.SetTypeId = 'FD' and o.OperationTypeId = t.OperationTypeId
	        WHERE Su.SupplyId = @SupplyId

		RETURN isNull(@RES,0)
	END	ELSE IF @Name = 'Длина транша'
	BEGIN
		If @SupplyId IS NOT NULL
			select	@Res = max(T.TranshDuration)
				From Supplies S
				Join SuppInTransh Sit on Sit.SupplyId = S.SupplyId
				Join Transhs T on T.TranshId = Sit.TranshId
		Else If @TranshId IS NOT NULL
			Select top 1 @Res = T.TranshDuration
				From Transhs T 
				Where T.TranshId = @TranshId

		set @Res = dbo.maxNum(0,@res)
		RETURN @RES
	END
	ELSE IF @Name = 'Общий срок финансирования'
	BEGIN
		select	@Res = 
			convert(numeric,	dbo.minDate(	@Dt,
												case	when sum(IsNull(o.OperAmount*t.Multy,0)) > 0 then null 
														else max(case when t.Multy=-1 then o.operDate else null end) end)
								- min(tr.TranshDate))
		from OperSets t
			join Operations o on o.SupplyId = @SupplyId and o.TranshId is not null and o.OperationTypeId = t.OperationTypeId
				and o.IsSummary = 0 and o.OperDate <= @dt
			join Transhs tr on tr.TranshId = o.TranshId
		where t.SetTypeId = 'FD'		
		
		set @Res = dbo.maxNum(0,@res)
		RETURN @RES
	END
	ELSE IF @Name = 'Срок финансирования'
	BEGIN
		select	@Res = 
			convert(numeric,	dbo.minDate(	@Dt,
												case	when sum(IsNull(o.OperAmount*t.Multy,0)) > 0 then null 
														else max(case when t.Multy=-1 then o.operDate else null end) end)
								- min(tr.TranshDate))
		from OperSets t
			join Operations o on o.TranshId = @transhId and o.OperationTypeId = t.OperationTypeId
				and o.IsSummary = 0 and o.OperDate <= @dt
			join Transhs tr on tr.TranshId = o.TranshId
		where t.SetTypeId = 'FD'

		set @Res = dbo.maxNum(0,@res)
		RETURN @RES
	END
	ELSE IF @Name = 'Срок подтвержденного финансирования' AND @TranshId IS NOT NULL
  --    -- Если передан код транша, то работаем по нему, иначе по коду поставки
  --    -- Показатель останавливается в дату погашения финансирования по траншу
  --    -- Если только часть выплат подвтерждена банком, то оставливаем показатель после оплаты Подтвержденного банком финансирования
	BEGIN
		select	@Res = 
			convert(numeric,	dbo.minDate(	@Dt,
												case	when sum(IsNull(o.OperAmount*t.Multy,0)) > 0 then null 
														else max(case when t.Multy=-1 then o.operDate else null end) end)
								- min(tr.TranshDate))
		from OperSets t
			join Operations o on o.TranshId = @transhId and o.OperationTypeId = t.OperationTypeId
				and o.IsSummary = 0 and o.OperDate <= @dt
			join Transhs tr on tr.TranshId = o.TranshId
		where t.SetTypeId = 'FD'
		having min(case when o.OperationTypeId = 'Финансирование' then o.BankDate when o.OperationTypeId = 'Удержанное финансирование' then o.OperDate end) < @dt

		set @Res = dbo.maxNum(0,@res)
		RETURN @RES
	END
	ELSE IF @Name = 'Срок подтвержденного финансирования' AND @TranshId IS NULL AND @SupplyId IS NOT NULL
	BEGIN
		select	@Res = 
			convert(numeric,	dbo.minDate(	@Dt,
												case	when sum(IsNull(o.OperAmount*t.Multy,0)) > 0 then null 
														else max(case when t.Multy=-1 then o.operDate else null end) end)
								- min(tr.TranshDate))
		from OperSets t
			join Operations o on o.SupplyId = @SupplyId and o.TranshId is not null and o.OperationTypeId = t.OperationTypeId
				and o.IsSummary = 0 and o.OperDate <= @dt
			left join Transhs tr on tr.TranshId = o.TranshId
		where t.SetTypeId = 'FD'
		having min(case when o.OperationTypeId = 'Финансирование' then o.BankDate when o.OperationTypeId = 'Удержанное финансирование' then o.OperDate end) < @dt

		set @Res = dbo.maxNum(0,@res)
		RETURN @RES
	END
	ELSE IF @Name = 'Срок подтвержденного финансирования включая дату выплаты' AND @TranshId IS NOT NULL
  --    -- Если передан код транша, то работаем по нему, иначе по коду поставки
  --    -- Показатель останавливается в дату погашения финансирования по траншу
  --    -- Если только часть выплат подвтерждена банком, то оставливаем показатель после оплаты Подтвержденного банком финансирования
	BEGIN
		select	@Res = 
			convert(numeric,	dbo.minDate(	@Dt,
												case	when sum(IsNull(o.OperAmount*t.Multy,0)) > 0 then null 
														else max(case when t.Multy=-1 then o.operDate else null end) end)
								- min(tr.TranshDate)) + 1.0
		from OperSets t
			join Operations o on o.TranshId = @transhId and o.OperationTypeId = t.OperationTypeId
				and o.IsSummary = 0 and o.OperDate <= @dt
			join Transhs tr on tr.TranshId = o.TranshId
		where t.SetTypeId = 'FD'
		having min(case when o.OperationTypeId = 'Финансирование' then o.BankDate when o.OperationTypeId = 'Удержанное финансирование' then o.OperDate end) < @dt

		set @Res = dbo.maxNum(0,@res)
		RETURN @RES
	END
	ELSE IF @Name = 'Срок подтвержденного финансирования включая дату выплаты' AND @TranshId IS NULL AND @SupplyId IS NOT NULL
	BEGIN
		select	@Res = 
			convert(numeric,	dbo.minDate(	@Dt,
												case	when sum(IsNull(o.OperAmount*t.Multy,0)) > 0 then null 
														else max(case when t.Multy=-1 then o.operDate else null end) end)
								- min(tr.TranshDate)) + 1.0
		from OperSets t
			join Operations o on o.SupplyId = @SupplyId and o.TranshId is not null and o.OperationTypeId = t.OperationTypeId
				and o.IsSummary = 0 and o.OperDate <= @dt
			left join Transhs tr on tr.TranshId = o.TranshId
		where t.SetTypeId = 'FD'
		having min(case when o.OperationTypeId = 'Финансирование' then o.BankDate when o.OperationTypeId = 'Удержанное финансирование' then o.OperDate end) < @dt

		set @Res = dbo.maxNum(0,@res)
		RETURN @RES
	END
	ELSE IF @Name = 'Срок подтвержденного финансирования до полной оплаты' AND @TranshId IS NOT NULL
 	BEGIN
		select	@Res = 
			convert(numeric,	dbo.minDate(	@Dt,
												case	when sum(IsNull(o.OperAmount*t.Multy,0)) > 0 then null 
														else max(case when t.Multy=-1 then o.operDate else null end) end)
								- min(tr.TranshDate))
		from OperSets t
			join Operations o on o.TranshId = @transhId and o.OperationTypeId = t.OperationTypeId
				and o.IsSummary = 0 and o.OperDate <= @dt
			join Transhs tr on tr.TranshId = o.TranshId
		where t.SetTypeId = 'AR'
		  and exists (select top 1 1 From Operations Ofin Where Ofin.TranshId = o.TranshId and  Ofin.OperationTypeId = 'Финансирование' and  Ofin.BankDate < @dt
					  union
					  select top 1 1 From Operations Ofin Where Ofin.TranshId = o.TranshId and  Ofin.OperationTypeId = 'Удержанное финансирование' and  Ofin.OperDate < @dt)

		set @Res = dbo.maxNum(0,@res)
		RETURN @RES
	END
	ELSE IF @Name = 'Срок подтвержденного финансирования до полной оплаты' AND @TranshId IS NULL AND @SupplyId IS NOT NULL
	BEGIN
		select	@Res = 
			convert(numeric,	dbo.minDate(	@Dt,
												case	when sum(IsNull(o.OperAmount*t.Multy,0)) > 0 then null 
														else max(case when t.Multy=-1 then o.operDate else null end) end)
								- min(tr.TranshDate))
		from OperSets t
			join Operations o on o.SupplyId = @SupplyId and o.TranshId is not null and o.OperationTypeId = t.OperationTypeId
				and o.IsSummary = 0 and o.OperDate <= @dt
			left join Transhs tr on tr.TranshId = o.TranshId
		where t.SetTypeId = 'AR'
		  and exists (select top 1 1 From Operations Ofin Where Ofin.SupplyId = o.SupplyId and  Ofin.OperationTypeId = 'Финансирование' and  Ofin.BankDate < @dt
					  union
					  select top 1 1 From Operations Ofin Where Ofin.SupplyId = o.SupplyId and  Ofin.OperationTypeId = 'Удержанное финансирование' and  Ofin.OperDate < @dt)
		set @Res = dbo.maxNum(0,@res)
		RETURN @RES
	END
	ELSE IF @Name = 'Срок подтвержденного финансирования до отсрочки' AND @TranshId IS NOT NULL
	BEGIN
		if exists(	
			select top 1 '*' From Operations O1
			where O1.TranshId = @TranshId
				and (	O1.OperationTypeId = 'Финансирование' and O1.BankDate < @Dt
						or O1.OperationTypeId = 'Удержанное финансирование'))
		select @res =
			convert(numeric,
						case when @Dt <= S.DelayDate then @Dt - (T.TranshDate)
								when @Dt > S.DelayDate then S.DelayDate - (T.TranshDate)
								else 0 end
						) 
		From Transhs T
		Join SuppInTransh SIT on SIT.TranshId = T.TranshId
		Join Supplies S on S.SupplyId = SIT.SupplyId
		where T.TranshId = @Transhid

		set @Res = dbo.maxNum(0,@res)
		RETURN @RES
	END
	ELSE IF @Name = 'Срок подтвержденного финансирования до отсрочки' AND @TranshId IS NULL AND @SupplyId IS NOT NULL
	BEGIN
		if exists(	
			select top 1 '*' From Operations O1
			where O1.SupplyId = @SupplyId
				and (	O1.OperationTypeId = 'Финансирование' and O1.BankDate < @Dt
						or O1.OperationTypeId = 'Удержанное финансирование'))
		Select @res = 
			convert(numeric,
							case when @Dt <= S.DelayDate then @Dt - MIN(T.TranshDate)
								 when @Dt > S.DelayDate then S.DelayDate - MIN(T.TranshDate)
								 else 0 end
						   ) 
		From Transhs T
		Join SuppInTransh SIT on SIT.TranshId = T.TranshId
		Join Supplies S on S.SupplyId = SIT.SupplyId
		Where Sit.SupplyId = @SupplyId
		group by s.DelayDate
		
		set @Res = dbo.maxNum(0,@res)
		RETURN @RES
	END

	-->> Срок ожидания оплаты
	ELSE IF (@Name = 'Срок ожидания оплаты')
	BEGIN
		IF (@TranshId IS NOT NULL)
		BEGIN
			select top 1 @Res = tr.TranshDuration, @TranshDate = tr.TranshDate from Transhs tr where tr.TranshId = @TranshId;
		
			if (@TranshDate != @Dt)
			begin
				set @Res = 0;
				
				set @TranshDate = (select min(case when o.OperationTypeId = 'Финансирование' then o.BankDate else o.OperDate end) 
									from Operations o where o.TranshId = @TranshId and o.OperationTypeId in (select t1.OperationTypeId from OperSets t1 where t1.SetTypeId = 'FD' and t1.Multy = 1));
				
				set @Res = convert(numeric, dbo.minDate(@Dt, (select top 1 supp.FactPaymDate from Supplies supp where supp.SupplyId = @SupplyId)) - @TranshDate);	
			end;

			set @Res = dbo.maxNum(0,@res);
			return @Res;
		END;
	
		IF (@TranshId IS NULL AND @SupplyId IS NOT NULL)
		BEGIN
			select @Res = max(Transhs.TranshDuration), @TranshDate = min(Transhs.TranshDate) 
			from SuppInTransh Sit
				join Transhs Transhs on Transhs.TranshId = Sit.TranshId
			where sit.SupplyId = @SupplyId;

			if (@TranshDate != @Dt)
			begin
				set @Res = 0;

				set @TranshDate = (select min(case when o.OperationTypeId = 'Финансирование' then o.BankDate else o.OperDate end) 
									from Operations o where o.SupplyId = @SupplyId and o.OperationTypeId in (select t1.OperationTypeId from OperSets t1 where t1.SetTypeId = 'FD' and t1.Multy = 1))

				set @Res = convert(numeric, dbo.minDate(@Dt, (select top 1 supp.FactPaymDate from Supplies supp where supp.SupplyId = @SupplyId)) - @TranshDate);	
			end;

			set @Res = dbo.maxNum(0,@res);
			return @Res;
		END;
	END
	--<< Срок ожидания оплаты
    ELSE IF @Name = 'Срок финансирования до отсрочки' AND @TranshId IS NOT NULL 
	BEGIN
		SELECT @Res =
			 dbo.maxNum(
					IsNull(
					   (Select convert(numeric,S.DelayDate - (T.TranshDate)) -- ???? под вопросом зачем так сделано
						  From Transhs T
						  Join SuppInTransh SIT on SIT.TranshId = T.TranshId
						  Join Supplies S on S.SupplyId = SIT.SupplyId
						 Where T.TranshId = @Transhid)
				   ,0)
				,0) 
		RETURN @RES
	END
	ELSE IF @Name = 'Срок финансирования до отсрочки' AND @TranshId IS NULL AND @SupplyId IS NOT NULL
	BEGIN
		SELECT @Res = 
			dbo.maxNum(
				IsNull(
				   (Select convert(numeric,S.DelayDate - MIN(T.TranshDate)) -- ???? под вопросом зачем так сделано
					  From Transhs T
					  Join SuppInTransh SIT on SIT.TranshId = T.TranshId
					  Join Supplies S on S.SupplyId = SIT.SupplyId
					 Where Sit.SupplyId = @SupplyId 
					Group By S.DelayDate)
               ,0)
            ,0) 
		RETURN @RES
	END
	ELSE IF @Name = 'Срок подтвержденного финансирования до ответственности дебитора' AND @TranshId IS NOT NULL 
	BEGIN 
		if exists(	
			select top 1 '*' From Operations O1
			where O1.TranshId = @TranshId
				and (	O1.OperationTypeId = 'Финансирование' and O1.BankDate < @Dt
						or O1.OperationTypeId = 'Удержанное финансирование'))
		Select	@res = 
			convert(numeric,
						case when @Dt <= S.ShipDate+CDL.DebtorRespons then @Dt - (T.TranshDate)
							 when @Dt > S.ShipDate+CDL.DebtorRespons then S.ShipDate+CDL.DebtorRespons - (T.TranshDate)  
							 else 0 end
					   ) 
		From Transhs T
		Join SuppInTransh SIT on SIT.TranshId = T.TranshId
		Join Supplies S on S.SupplyId = SIT.SupplyId
		Join ClientDebtorLink CDL on CDL.ClientDebtorLinkId = T.ClientDebtorLinkId
		Where T.TranshId = @Transhid
		
		set @Res = dbo.maxNum(0,@res)
		RETURN @RES
	END
	ELSE IF @Name = 'Срок подтвержденного финансирования до ответственности дебитора' AND @TranshId IS NULL AND @SupplyId IS NOT NULL
	BEGIN 
		if exists(	
			select top 1 '*' From Operations O1
			where O1.SupplyId = @SupplyId
				and (	O1.OperationTypeId = 'Финансирование' and O1.BankDate < @Dt
						or O1.OperationTypeId = 'Удержанное финансирование'))
		Select @res = 
			convert(numeric,
						case when @Dt <= S.ShipDate+CDL.DebtorRespons then @Dt - MIN(T.TranshDate)
							 when @Dt > S.ShipDate+CDL.DebtorRespons then S.ShipDate+CDL.DebtorRespons - MIN(T.TranshDate)  
							 else 0 end
					   ) 
		From Transhs T
		Join SuppInTransh SIT on SIT.TranshId = T.TranshId
		Join Supplies S on S.SupplyId = SIT.SupplyId
		Join ClientDebtorLink CDL on CDL.ClientDebtorLinkId = T.ClientDebtorLinkId
		Where Sit.SupplyId = @SupplyId
		Group By S.ShipDate, CDL.DebtorRespons

		set @Res = dbo.maxNum(0,@res)
		RETURN @RES
	END  
	ELSE IF @Name = 'Срок подтвержденного финансирования до просрочки по договору' AND @TranshId IS NOT NULL
	BEGIN
		if exists(	
			select top 1 '*' From Operations O1
			where O1.TranshId = @TranshId
				and (	O1.OperationTypeId = 'Финансирование' and O1.BankDate < @Dt
						or O1.OperationTypeId = 'Удержанное финансирование'))
		Select @res =  
			convert(numeric,
						case when @Dt <= S.DelayDate+IsNull(CM.DelayLimit,0) then @Dt - (T.TranshDate)
							 when @Dt > S.DelayDate+IsNull(CM.DelayLimit,0) then S.DelayDate+IsNull(CM.DelayLimit,0) - (T.TranshDate)
							 else 0 end
					   ) 
		from Transhs T
		Join SuppInTransh SIT on SIT.TranshId = T.TranshId
		Join Supplies S on S.SupplyId = SIT.SupplyId
		Join ClientModels CM on S.ClientModelId = CM.ClientModelId
		Where T.TranshId = @Transhid

		set @Res = dbo.maxNum(0,@res)
		RETURN @RES
	END
	ELSE IF @Name = 'Срок подтвержденного финансирования до просрочки по договору' AND @TranshId IS NULL AND @SupplyId IS NOT NULL
	BEGIN
		if exists(	
			select top 1 '*' From Operations O1
			where O1.SupplyId = @SupplyId
				and (	O1.OperationTypeId = 'Финансирование' and O1.BankDate < @Dt
						or O1.OperationTypeId = 'Удержанное финансирование'))
		Select @res =  
			convert(numeric,
						case when @Dt <= S.DelayDate+IsNull(CM.DelayLimit,0) then @Dt - MIN(T.TranshDate)
							 when @Dt > S.DelayDate+IsNull(CM.DelayLimit,0) then S.DelayDate+IsNull(CM.DelayLimit,0) - MIN(T.TranshDate)
							 else 0 end
					   ) 
		From Transhs T
		Join SuppInTransh SIT on SIT.TranshId = T.TranshId
		Join Supplies S on S.SupplyId = SIT.SupplyId
		Join ClientModels CM on S.ClientModelId = CM.ClientModelId
		Where Sit.SupplyId = @SupplyId
		Group By CM.DelayLimit, S.DelayDate

		set @Res = dbo.maxNum(0,@res)
		RETURN @RES
	END 		
	ELSE IF @Name = 'Срок подтвержденного финансирования до последнего выходного дня' AND @TranshId IS NOT NULL 
	BEGIN
		if exists(	
			select top 1 '*' From Operations O1
			where O1.TranshId = @TranshId
				and (	O1.OperationTypeId = 'Финансирование' and O1.BankDate < @Dt
						or O1.OperationTypeId = 'Удержанное финансирование'))
		Select @res = 
			convert(numeric,dbo.minDate(@Dt,dbo.GetWorkDay(S.DelayDate)) - (T.TranshDate))
		From Transhs T
		Join SuppInTransh SIT on SIT.TranshId = T.TranshId
		Join Supplies S on S.SupplyId = SIT.SupplyId
		Where T.TranshId = @Transhid 
		
		set @Res = dbo.maxNum(0,@res)
		RETURN @RES
	END
	ELSE IF @Name = 'Срок подтвержденного финансирования до последнего выходного дня' AND @TranshId IS NULL AND @SupplyId IS NOT NULL
	BEGIN
		if exists(	
			select top 1 '*' From Operations O1
			where O1.SupplyId = @SupplyId
				and (	O1.OperationTypeId = 'Финансирование' and O1.BankDate < @Dt
						or O1.OperationTypeId = 'Удержанное финансирование'))
		Select @res = convert(numeric,dbo.minDate(@Dt,dbo.GetWorkDay(S.DelayDate)) - MIN(T.TranshDate))
		From Transhs T
		join SuppInTransh SIT on SIT.TranshId = T.TranshId
		Join Supplies S on S.SupplyId = SIT.SupplyId
		Where Sit.SupplyId = @SupplyId
		Group By S.DelayDate
		
		set @Res = dbo.maxNum(0,@res)
		RETURN @RES
	END 	
	ELSE IF @Name = 'Срок ответственности дебитора' 
	BEGIN
		SELECT @Res =  
			dbo.maxNum(IsNull((Select sum(IsNull(convert(numeric, dbo.minDate(@Dt, s.FactPaymDate) - (S.ShipDate+CDL.DebtorRespons)),0)) 
								 From Supplies S
								 Join ClientDebtorLink CDL on CDL.ClientDebtorLinkId = S.ClientDebtorLinkId
								Where S.SupplyId = @SupplyId),0),0)
		RETURN @RES
	END
	ELSE IF @Name = 'Просрочка оплаты поставки' AND @TranshId IS NOT NULL
	BEGIN 
		SELECT @Res = 
			dbo.maxNum((Select convert(numeric, dbo.MinDate(@Dt,Su2.FactPaymDate) - Su2.DelayDate) From SuppInTransh Sit2
			             Join Supplies Su2 on Su2.SupplyId = Sit2.SupplyId
                         Where Sit2.TranshId = @TranshId),0)
		RETURN @RES
	END
	ELSE IF @Name = 'Просрочка оплаты поставки' AND @TranshId IS NULL AND @SupplyId IS NOT NULL
	BEGIN 
		SELECT @Res = 
			dbo.maxNum((Select convert(numeric, dbo.MinDate(@Dt,Su2.FactPaymDate) - Su2.DelayDate) From Supplies Su2 
                         Where Su2.SupplyId = @SupplyId),0)
		RETURN @RES
	END
	ELSE IF @Name = 'Просрочка оплаты возврата' 
	BEGIN 
		SELECT @Res = 
			 dbo.maxNum((SELECT CONVERT(NUMERIC(28,12),@Dt - D.PaymDate) FROM OperDocs D WHERE D.OperDocId=@OpId and D.PaymStateId!='Оплачен'),0)                
		RETURN @RES
	END
	ELSE IF @Name = 'Просрочка льготного периода'
	BEGIN
		-- 365 - просто большое число
		select @Res = 
			convert(numeric(28,12), 
				dbo.MinDate(@Dt,dbo.GetWorkDay(s.DelayDate + case when ISNULL(s.TranshRegressPeriod,0) = 0 then 365 else s.TranshRegressPeriod end))
				- dbo.GetWorkDay((s.DelayDate + IsNULL(IsNULL(s.GracePeriod,IsNull(cdl.GracePeriod,cm.GracePeriod)),0))))
		from Supplies s
		join ClientDebtorLink cdl on cdl.ClientDebtorLinkId = s.ClientDebtorLinkId
		Join ClientModels cm on cm.ClientModelId = s.ClientModelId
		where s.SupplyId = @SupplyId
		
		set @Res = dbo.maxNum(0,@res)
		RETURN @RES
	END
	ELSE IF @Name = 'Просрочка льготного периода без остановки' 
	BEGIN 
		-- 365 - просто большое число
		select @Res = 
			convert(numeric(28,12), 
				@Dt - dbo.GetWorkDay((s.DelayDate + IsNULL(IsNULL(s.GracePeriod,IsNull(cdl.GracePeriod,cm.GracePeriod)),0))))
		from Supplies s
		Join ClientDebtorLink cdl on cdl.ClientDebtorLinkId = s.ClientDebtorLinkId
		Join ClientModels cm on cm.ClientModelId = s.ClientModelId
		where s.SupplyId = @SupplyId
		
		set @Res = dbo.maxNum(0,@res)
		RETURN @RES
	END  
	ELSE IF @Name = 'Просрочка оплаты по счету'
	BEGIN
		SELECT @Res = 
			IsNull((Select top 1 convert(Numeric, @Dt - dbo.AddDays(Ord.RegDate, isnull(isnull(C.OrderDelay,C_cdl.OrderDelay),C_Cm.OrderDelay), isnull(isnull(C.DelayTypeId,C_cdl.DelayTypeId),C_Cm.DelayTypeId))) 
					  From Operations O (nolock)  
				                join      Orders			Ord (nolock) on Ord.OrderId = O.OrderId
								left join Supplies			S	(nolock) on S.SupplyId = O.SupplyId
								left join Contracts			C	(nolock) on C.ContractId  = S.AddDelayContractId and C.OrderDelay > 0 -- Соглашение о пролонгации
								left join ClientDebtorLink	Cdl (nolock) on Cdl.ClientDebtorLinkId = O.ClientDebtorLinkId
								Left Join Contracts			C_cdl (nolock) on C_cdl.ContractId = Cdl.ContractId and C_cdl.OrderDelay > 0  -- договор поставки
								left join ClientModels		Cm	(nolock) on Cm.ClientModelId = O.ClientModelId
								Left Join Contracts			C_Cm (nolock) on C_Cm.ContractId = Cm.ContractId and C_Cm.OrderDelay > 0  -- договор факторинга
								Where O.OperationId = @OpId and O.ReceptDate < @Dt),0) 
		RETURN dbo.maxNum(0,@res)
	END	
	ELSE IF @Name = 'Просрочка оплаты комиссий' 
	BEGIN
		SELECT @Res = 
			IsNull((Select TOP 1 convert(Numeric, @Dt - dbo.GVReceptDate(O.OperationId))
					  From Operations O Where O.OperationId = @OpId and O.ReceptDate < @Dt ),0)
		RETURN @RES
	END
	ELSE IF @Name = 'Просрочка льготного периода оплаты комиссий'
	BEGIN
		SELECT @Res = 
			dbo.maxNum(IsNull((Select dbo.maxNum(0, convert(numeric, @Dt - O2.ReceptDate)) From Operations O2 Where O2.OperationId = @OpId),0)
					  -IsNull((Select IsNULL(Su2.GracePeriod,IsNull(CDl2.GracePeriod,Cm2.GracePeriod)) 
                                 From Operations O2
								 Join Supplies Su2 on Su2.SupplyId = O2.SupplyId 
								 Join ClientModels Cm2 on Cm2.ClientModelId = Su2.ClientModelId
								 Join ClientDebtorLink CDL2 on Su2.ClientDebtorLinkId = CDL2.ClientDebtorLinkId 
							    Where O2.OperationId = @OpId),0),0)
		RETURN @RES
	END
	ELSE IF @Name = 'Льготный период финансирования'
	BEGIN
		SELECT @Res = 
			(Select max(Convert(numeric, dbo.minDate(@dt,S.DelayDate + IsNULL(S.GracePeriod,IsNull(CDl2.GracePeriod,Cm2.GracePeriod))) - T.TranshDate))
			   From Transhs T
			   join SuppInTransh Sit on T.TranshId = Sit.TranshId
			   Join Supplies S on Sit.SupplyId = S.SupplyId
			   Join ClientModels Cm2 on Cm2.ClientModelId = S.ClientModelId
			   Join ClientDebtorLink CDL2 on S.ClientDebtorLinkId = CDL2.ClientDebtorLinkId
			  Where (@TranshId IS NULL or T.TranshId = @TranshId) 
				and (@SupplyId Is NULL or S.SupplyId = @SupplyId))
		RETURN @RES
	END
	ELSE IF @Name = 'Просрочка регресса'
	BEGIN
		SELECT @Res = 
			dbo.MaxNum(IsNull((Select convert(numeric, @Dt - dbo.GetWorkDay((Su2.DelayDate + Su2.TranshRegressPeriod))) From Supplies Su2 Where Su2.SupplyId = @SupplyId),0),0)
		RETURN @RES
	END   
	ELSE IF @Name = 'Дебиторская задолженность по поставке'
	BEGIN
		SELECT @Res = 
			dbo.MaxNum(0,
					isnull((	select sum( case	when t1.Multy = 1 then IsNull(o1.OperAmount*t1.Multy,0)
													when t1.Multy = -1 and o1.OperDate < @Dt then IsNull(o1.OperAmount*t1.Multy,0)
													else 0 end)
								from OperSets t1 with(nolock)
								Join Operations o1 on o1.OperationTypeId = t1.OperationTypeId
								where t1.SetTypeId = 'AR' and o1.SupplyId = @SupplyId 
								  and o1.IsSummary = 0 ),0))
		RETURN @RES
	END	 
	ELSE IF @Name = 'Просроченная дебиторская задолженность по поставке'
	BEGIN
		SELECT @Res = 
			dbo.MaxNum(0,
					isnull((select sum( case when t1.Multy = 1 then IsNull(o1.OperAmount*t1.Multy,0)
											 when t1.Multy = -1 and o1.OperDate <= @Dt then IsNull(o1.OperAmount*t1.Multy,0)
											 else 0 end)
								from Supplies s
								join Operations o1 on o1.SupplyId = s.SupplyId
								join OperSets t1 on t1.OperationTypeId = o1.OperationTypeId
								where convert(datetime, dbo.GetNValueFromDt('Превышение срока оплаты по регрессу', NULL, S.SupplyId, @Dt, NULL, NULL)) <= @Dt
								  and t1.SetTypeId = 'AR' 
								  and o1.SupplyId = @SupplyId 
								  and o1.IsSummary = 0),0))
		RETURN @RES
	END	
	ELSE IF @Name in ('Сумма операции','Сумма погашения финансирования')
	BEGIN
		SELECT @Res = 
			CASE WHEN @OpId IS NULL THEN IsNull(@Amount,0) ELSE IsNull((Select top 1 O.OperAmount From Operations O Where O.OperationId = @OpId),0) END
		RETURN @RES
	END    
	ELSE IF @Name = 'Отсрочка по поставке' 
	BEGIN
		SELECT @Res =
			IsNull((Select sum(IsNull(S.PaymDelay,0)) From Supplies S Where S.SupplyId = @SupplyId),0)
		RETURN @RES
	END
	ELSE IF @Name = 'Текущая отсрочка по поставке'
	BEGIN
		SELECT @Res = 
			dbo.maxNum(IsNull((Select sum(IsNull(convert(numeric(28,2), dbo.minDate(@Dt, s.FactPaymDate) - S.ShipDate),0)) 
                                 From Supplies S Where S.SupplyId = @SupplyId),0),0)         
		RETURN @RES
	END
	ELSE IF @Name = 'Срок первой отсрочки'
	BEGIN
		SELECT @Res = 
			dbo.maxNum(IsNull((Select sum(IsNull(convert(numeric(28,2), dbo.minDate(@Dt, dbo.MinDate(S.ShipDate + S.FirstDelay,S.FactPaymDate)) - S.ShipDate),0)) 
                                 From Supplies S Where S.SupplyId = @SupplyId and IsNULL(S.FirstDelay,0) <> 0),0),0)
		RETURN @RES
	END
	ELSE IF @Name = 'Срок второй отсрочки'
	BEGIN
		SELECT @Res = 
			dbo.maxNum(IsNull((Select sum(IsNull(convert(numeric(28,2), dbo.minDate(@Dt, dbo.MinDate(S.ShipDate + IsNULL(S.FirstDelay,0) + S.SecondDelay,S.FactPaymDate)) - (S.ShipDate + IsNULL(S.FirstDelay,0))),0)) 
                                 From Supplies S Where S.SupplyId = @SupplyId and IsNULL(S.SecondDelay,0) <> 0),0),0)
		RETURN @RES
	END
    ELSE IF @Name = 'Просрочка по договору' AND @TranshId IS NOT NULL
    BEGIN 
		SELECT @Res = 
			dbo.maxNum((Select convert(numeric, dbo.MinDate(@Dt,Su2.FactPaymDate) - Su2.DelayDate - IsNull(CM2.DelayLimit,0)) 
                          From SuppInTransh Sit2
						  Join Supplies Su2 on Su2.SupplyId = Sit2.SupplyId
						  Join ClientModels CM2 on CM2.ClientModelId = Su2.ClientModelId
                         Where Sit2.TranshId = @TranshId),0)
		RETURN @RES                                                      
	END
	    ELSE IF @Name = 'Просрочка по договору' AND @TranshId IS NULL AND @SupplyId IS NOT NULL
    BEGIN 
		SELECT @Res = 
			dbo.maxNum((Select convert(numeric, dbo.MinDate(@Dt,Su2.FactPaymDate) - Su2.DelayDate - IsNull(CM2.DelayLimit,0)) 
                          From Supplies Su2
						  Join ClientModels CM2 on CM2.ClientModelId = Su2.ClientModelId
                         Where Su2.SupplyId = @SupplyId),0)
		RETURN @RES                                                      
	END
	ELSE IF @Name = 'Просроченный возврат прямого платежа'
	BEGIN 
		SELECT @Res = 
			dbo.MaxNum((SELECT MAX(IsNull(Op.OperAmount,0))-SUM(IsNull(Ld.OperDocAmount,0)) 
						  FROM Operations Op
		                  Left Join OperDocs Ld on Ld.LinkDocId = Op.OperDocId
		                 WHERE Op.OperationId = @OpId),0)
		RETURN @RES
	END
	ELSE IF @Name = 'Просрочка возврата прямого платежа'
	BEGIN
		SELECT @Res = 
		  CASE WHEN dbo.MaxNum((SELECT MAX(IsNull(Op.OperAmount,0))-SUM(IsNull(Ld.OperDocAmount,0)) 
								  FROM Operations Op
								  Left Join OperDocs Ld on Ld.LinkDocId = Op.OperDocId
								 WHERE Op.OperationId = @OpId),0)>0 
		       THEN dbo.MaxNum((Select CONVERT(Numeric(28,12), @Dt-(Op.OperDate+(Select sp.TermReturnDirectPayment From SysParameters sp))) 
		                          FROM Operations Op WHERE Op.OperationId=@OpId),0)
		      ELSE 0 END 
		RETURN @RES
	END
	ELSE IF @Name = 'Превышение срока оплаты по регрессу'
	BEGIN
		SELECT @Res = 
			dbo.maxNum(isNULL((Select Top 1 convert(numeric,@Dt - dbo.AddDays( dbo.GetWorkDay((S.DelayDate + S.TranshRegressPeriod)),IsNULL(CM.CountDay4PayOnRegr,0),CM.PeriodType4PayOnRegr))
								 From Supplies S
								 Join ClientModels Cm on Cm.ClientModelId = S.ClientModelId 
								 Where S.SupplyId = @SupplyId),0),0)   
		RETURN @RES                              
	END
	ELSE IF @Name = 'Просрочка с первого рабочего дня оплаты поставки' AND @TranshId IS NOT NULL
	BEGIN
		SELECT @Res =  
			dbo.maxNum((Select convert(numeric, dbo.MinDate(@Dt,Su2.FactPaymDate) - dbo.GetWorkDay(Su2.DelayDate),0)
                         From SuppInTransh Sit2
						 Join Supplies Su2 on Su2.SupplyId = Sit2.SupplyId
                        Where Sit2.TranshId = @TranshId),0)       
		RETURN @RES
	END   
	ELSE IF @Name = 'Просрочка с первого рабочего дня оплаты поставки' AND @TranshId IS NULL AND @SupplyId IS NOT NULL
	BEGIN
		SELECT @Res =  
			dbo.maxNum((Select convert(numeric, dbo.MinDate(@Dt,Su2.FactPaymDate) - dbo.GetWorkDay(Su2.DelayDate),0)
                          From Supplies Su2 Where Su2.SupplyId = @SupplyId),0)       
		RETURN @RES
	END
	ELSE IF @Name = ' Срок дебиторской задолженности' AND @SupplyId IS NOT NULL --исчисляется от «даты отгрузки» до даты полного погашения дебиторской задолженности по поставке.
	BEGIN
		select	@Res = 
			convert(numeric,	dbo.minDate(	@Dt,
												case	when sum(IsNull(o.OperAmount*t.Multy,0)) > 0 then null 
														else max(case when t.Multy=-1 then o.operDate else null end) end)
								- min(s.ShipDate))
		from OperSets t
			join Operations o on o.SupplyId = @SupplyId and o.OperationTypeId = t.OperationTypeId
				and o.IsSummary = 0 and o.OperDate <= @dt
			left join Supplies S on S.SupplyId = @SupplyId
		where t.SetTypeId = 'AR'

		set @Res = dbo.maxNum(0,@res)
		RETURN @RES
	END
	----------------------------
	-- Агрегированные показатели  
	----------------------------
	
	/*
	Среднедневная сумма непогашенного финансирования по договору факторинга за месяц – суммируется 
	все выплаченное финансирование по договору факторинга за целый предыдущий (относительно даты 
	начисления комиссии) месяц (с даты начала месяца до даты окончания месяца) с вычетом погашения 
	финансирования (набор операций FD «Задолженность за финансирование») и делится на количество 
	рабочих дней в месяце.
	*/
	ELSE IF @Name = 'Среднедневная сумма непогашенного финансирования по договору факторинга за месяц'
    BEGIN
		select @res = sum(IsNull(o.OperAmount*t.Multy,0))/p.wd
		from(
			select	wk.ClientModelId, 
					wd=wk.n3/7*5+case when wk.n1>2 then wk.n1-2 else 0 end+case when wk.n2<5 then wk.n2+1 else 5 end
			FROM(
				Select d.ClientModelId,
					   n1 = 7-datediff(D,0,d.bm)%7
					  ,n2 = datediff(D,0,d.em)%7
				      ,n3 = datediff(D,d.bm,d.em)-(7-datediff(D,0,d.bm)%7)-(datediff(D,0,d.em)%7)
				from(
					select s.CloseDay, s.ClientModelId,
						   em = convert(Datetime, OperDate - day(OperDate)), 
						   bm = convert(datetime,OperDate - day(OperDate) - day(OperDate - day(OperDate)) + 1) 
					from Operations o
					join WorkCalendar wc on wc.WorkDate = OperDate
					join Supplies s on s.SupplyId = o.SupplyId 
					where OperationTypeId like '%начисление%' and s.ClientModelId = @ClMod and (s.CloseDay >= @dt or s.CloseDay is null)
					) as d
--				where d.ClientModelId = @ClMod and (d.CloseDay >= @dt or d.CloseDay is null)
			) as wk
		)as p
		join OperSets t with(nolock)  on t.SetTypeId <> 'FD'
		join Operations o on o.ClientModelId = p.ClientModelId and o.OperationTypeId = t.OperationTypeId and o.IsSummary = 0 and o.OperDate < @dt 
		group by p.ClientModelId, p.wd

		set @Res = dbo.maxNum(0,@res)
		RETURN @RES
	END
	/*
	Среднедневная сумма непогашенного финансирования по дебитору за месяц – суммируется все выплаченное 
	финансирование по всем договорам поставки дебитора, связанным с одним договором факторинга, за целый 
	предыдущий (относительно даты начисления комиссии) месяц (с даты начала месяца до даты окончания 
	месяца) с вычетом погашения финансирования (набор операций FD «Задолженность за финансирование») и 
	делится на количество рабочих дней в месяце.
	*/
	ELSE IF @Name = 'Среднедневная сумма непогашенного финансирования по дебитору за месяц'
    BEGIN

		select @res = sum(IsNull(o.OperAmount*t.Multy,0))/p.wd
		from(
			select	wk.SupplyId, 
					wd=wk.n3/7*5+case when wk.n1>2 then wk.n1-2 else 0 end+case when wk.n2<5 then wk.n2+1 else 5 end
			FROM(
				Select d.SupplyId,
					   n1 = 7-datediff(D,0,d.bm)%7
					  ,n2 = datediff(D,0,d.em)%7
				      ,n3 = datediff(D,d.bm,d.em)-(7-datediff(D,0,d.bm)%7)-(datediff(D,0,d.em)%7)
				from(
					select s.SupplyId, s.CloseDay, s.ClientModelId,
						   em = convert(Datetime, OperDate - day(OperDate)), 
						   bm = convert(datetime,OperDate - day(OperDate) - day(OperDate - day(OperDate)) + 1) 
					from Operations o
					join WorkCalendar wc on wc.WorkDate = OperDate
					join Supplies s on s.SupplyId = o.SupplyId 
					where OperationTypeId like '%начисление%' and s.ClientModelId = @ClMod and (s.CloseDay >= @dt or s.CloseDay is null)
					) as d
--				where d.ClientModelId = @ClMod and (d.CloseDay >= @dt or d.CloseDay is null)
			) as wk
		)as p
		join OperSets t with(nolock)  on t.SetTypeId <> 'FD'
		join Operations o on o.SupplyId = p.SupplyId and o.OperationTypeId = t.OperationTypeId and o.IsSummary = 0 and o.OperDate < @dt 
		group by p.SupplyId, p.wd

		set @Res = dbo.maxNum(0,@res)
		RETURN @RES
	END

    ELSE IF @Name = 'Дебиторская задолженность по клиенту'
    BEGIN
		select @res = sum(IsNull(o.OperAmount*t.Multy,0))
		from (
			select s.SupplyId
			from Supplies s
				join Operations o on o.SupplyId = s.SupplyId and o.OperationTypeId in ('Финансирование','Удержанное финансирование') 
			where s.ClientModelId = @ClMod and (s.CloseDay >= @dt or s.CloseDay is null)
			group by s.SupplyId
			having min(case when o.OperationTypeId = 'Финансирование' then o.BankDate when o.OperationTypeId = 'Удержанное финансирование' then o.OperDate end) < @dt
		) as d
		join OperSets t with(nolock)  on t.SetTypeId = 'AR'
		join Operations o on o.SupplyId = d.SupplyId and o.OperationTypeId = t.OperationTypeId and o.IsSummary = 0 and o.OperDate < @dt

		set @Res = dbo.maxNum(0,@res)
		RETURN @RES
	END
	ELSE IF @Name = 'Дебиторская задолженость по договору факторинга (D2фин)'
	BEGIN
		SELECT @Res =
			dbo.MaxNum(0,
					isnull((	select sum( case	when t1.Multy = 1 then IsNull(o1.OperAmount*t1.Multy,0)
													when t1.Multy = -1 and o1.OperDate < @Dt then IsNull(o1.OperAmount*t1.Multy,0)
													else 0 end)
								from OperSets t1 (nolock)
								Join Operations o1 (nolock) on o1.OperationTypeId = t1.OperationTypeId
								Join ClientDebtorLink cdl1 with(nolock) on o1.ClientDebtorLinkId = cdl1.ClientDebtorLinkId
								where t1.SetTypeId = 'AR' and o1.ClientModelId = @ClMod
									and o1.IsSummary = 0 and isnull(cdl1.IsConfidential,0)=0 ),0))
		RETURN @RES
	END
	ELSE IF @Name = 'Дебиторская задолженность по контракту (Dфин)'
	BEGIN 
		SELECT @Res = 
			dbo.MaxNum(0,
					isnull((	select sum( case	when t1.Multy = 1 then IsNull(o1.OperAmount*t1.Multy,0)
													when t1.Multy = -1 and o1.OperDate < @Dt then IsNull(o1.OperAmount*t1.Multy,0)
													else 0 end)
								from OperSets t1 (nolock)
								Join Operations o1 (nolock) on o1.OperationTypeId = t1.OperationTypeId
								where t1.SetTypeId = 'AR' and o1.ClientDebtorLinkId = @CDLink 
									and o1.IsSummary = 0 ),0))
		RETURN @RES
	END
	ELSE IF @Name = 'Комиссия за расчетный период'
	BEGIN
		SELECT @Res = 
			IsNULL((Select sum(case when ct.VatInclude = 1 then isnull(Op.OperAmount,0) else isnull(Op.NoneVatAmount,0) end)
                      From Operations Op 
					  Join ComissionTypes CT (nolock) on Ct.CommissionTypeId = Op.CommissionTypeId
                     Where Op.ClientModelId = @ClMod 
                       and Op.OperationTypeId in ('Начисление комиссии SF1','Начисление комиссии SF2')
                       and Op.OperDate between dbo.GetSDtOnCalcPeriod(@Dt,@ClMod) and dbo.GetEDtOnCalcPeriod(@Dt,@ClMod) ),0)
		RETURN @RES
	END
	ELSE IF @Name = 'Коэффициент концентрации дебиторской задолженности'
	BEGIN
		SELECT @Res = 
			(SELECT MAX(convert(numeric(28,12),D.Value)) FROM TGetParamByDt('Концентрация дебиторской задолженности', @Dt, convert(varchar(60),@ClMod)) D)  
		RETURN @RES
	END
	ELSE IF @Name = 'Оборот по договору факторинга' 
	BEGIN
		declare @sDt datetime,
				@eDt datetime

		if @TranshId is null
		begin
			select	@sDt = dbo.FirstDateMth(tr.TranshDate), 
					@eDt = dbo.LastDateMth(tr.TranshDate)
			from Transhs tr where tr.TranshId = @TranshId
		end else
		begin
			select	top 1
					@sDt = dbo.FirstDateMth(o.OperDate), 
					@eDt = dbo.LastDateMth(o.OperDate)
			from Operations o where o.SupplyId = @SupplyId and o.OperationTypeId in (select operSetsLoc.OperationTypeId from OperSets operSetsLoc where operSetsLoc.SetTypeId = 'RS') and o.IsSummary = 0
		end

		select @Res = sum(IsNull(o.OperAmount,0))
		from Operations o
		where	o.ClientModelId = @ClMod
			and o.OperationTypeId = 'Регистрация поставки'
			and o.IsSummary = 0
			and o.OperDate between @sDt and @eDt
		RETURN @RES
	END                                
	ELSE IF @Name = 'Оборот за последние 30 дней по договору факторинга' 
	BEGIN

		if @TranshId is not null
		begin
			select	top 1 
					@sDt = Dbo.AddDays(tr.TranshDate,-31,'В календарных днях'), 
					@eDt = Dbo.AddDays(tr.TranshDate,-1,'В календарных днях')
			from Transhs tr (nolock) where tr.TranshId = @TranshId
		end else
		begin
			select	
					@sDt = Dbo.AddDays(min(o.OperDate),-31,'В календарных днях'), 
					@eDt = Dbo.AddDays(min(o.OperDate),-1,'В календарных днях')
			from Operations o (nolock)
			join OperSets T on T.SetTypeId = 'FD' and T.Multy = 1 and T.OperationTypeId = o.OperationTypeId
			where o.SupplyId = @SupplyId and o.IsSummary = 0
		end

		select @Res = sum(IsNull(o.OperAmount,0))
		from Operations o
		where	o.ClientModelId = @ClMod
			and o.OperationTypeId = 'Регистрация поставки'
			and o.IsSummary = 0
			and o.OperDate between @sDt and @eDt
		RETURN isNUll(@RES,0)
	END                                
	ELSE IF @Name = 'Задолженность по финансированию по договору' 
	BEGIN
		select @Res = sum(IsNull(o.OperAmount*T.Multy,0))
		  from Operations o
		  join OperSets T on T.OperationTypeId = o.OperationTypeId and T.SetTypeId = 'FD'
		where	o.ClientModelId = @ClMod
			and o.IsSummary = 0
			and o.OperDate < @Dt
		RETURN @RES
	END 
	ELSE IF @Name = 'Овердрафт' and @Dt is not null and @OpId is not null --база нач.коммиссии для овердрафта - день выписки - остаток по выписке
	BEGIN
		select @Res = case when ab.AmountEnd < 0 then ab.AmountEnd*(-1) else 0 end
		from AccBalances  ab 
		where ab.BankAccountId = @OpId and ab.BalanceDate = @Dt

		RETURN isnull(@RES,0)
	END
	ELSE IF @Name = 'Резервирование лимита финансирования договора факторинга' 
	BEGIN	
		If @OpId is not null 
		Begin
			SELECT 
				@Res = case when H.PeriodRowNum = 1 then H.Val
							when H.PeriodRowNum > 1 then dbo.maxNum(H.Val-H.ReservLim,0)
					   end
			FROM ClientModels cm
			CROSS APPLY dbo.TGetLimReservHistory(cm.ClientModelId, @Dt, 'Лимит финансирования', null, @OpId) as H	
			WHERE cm.ClientModelId = @ClMod	
			AND @Dt = H.DateFrom 
		End;		

		RETURN isnull(@RES,0)
	END
	ELSE IF @Name = 'Резервирование лимита фондирования договора факторинга' 
	BEGIN			
		If @OpId is not null 
		Begin
			SELECT 
				@Res = case when H.PeriodRowNum = 1 then H.Val
							when H.PeriodRowNum > 1 then dbo.maxNum(H.Val-H.ReservLim,0)
					   end
			FROM ClientModels cm
			CROSS APPLY dbo.TGetLimReservHistory(cm.ClientModelId, @Dt, 'Лимит фондирования', null, @OpId) as H	
			WHERE cm.ClientModelId = @ClMod	
			AND @Dt = H.DateFrom 
		End;

		RETURN isnull(@RES,0)
	END  
	ELSE IF @Name = 'Срок резервирования лимита финансирования договора факторинга' 
	BEGIN			
		If @OpId is not null 
		Begin
			SELECT 
				@Res = H.DaysUntilPeriodEnd
			FROM ClientModels cm
			CROSS APPLY dbo.TGetLimReservHistory(cm.ClientModelId, @Dt, 'Лимит финансирования', null, @OpId) as H	
			WHERE cm.ClientModelId = @ClMod	
			AND H.DateFrom = @Dt 
			AND (H.PeriodRowNum = 1 or H.PeriodRowNum > 1 and H.Val-H.ReservLim > 0) -- проверка, что происходит установка лимита или увеличение лимита 
		End;

		RETURN isnull(@RES,0)	
	END    
	ELSE IF @Name = 'Срок резервирования лимита фондирования договора факторинга' 
	BEGIN
		If @OpId is not null 
		Begin
			SELECT 
				@Res = H.DaysUntilPeriodEnd
			FROM ClientModels cm
			CROSS APPLY dbo.TGetLimReservHistory(cm.ClientModelId, @Dt, 'Лимит фондирования', null, @OpId) as H	
			WHERE cm.ClientModelId = @ClMod	
			AND H.DateFrom = @Dt 
			AND (H.PeriodRowNum = 1 or H.PeriodRowNum > 1 and H.Val-H.ReservLim > 0) -- проверка, что происходит установка лимита или увеличение лимита 
		End;

		RETURN isnull(@RES,0)
	END     
    ELSE SELECT @Res = 0        

  RETURN @RES; 
END
























































