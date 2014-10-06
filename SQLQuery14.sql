declare @objectname sysname = 'Configuration.usp_VersionControl_GetList';

SELECT SCHEMA_NAME(SCHEMA_ID) AS [Schema],
SO.Name AS [ObjectName],
SO.Type_Desc AS [ObjectType (UDF/SP)],
PM.Parameter_ID AS [ParameterID],
case 
when pm.system_type_id = pm.user_type_id then 'system_type'
else 'user_type'
end as [TypeDescr],
CASE
WHEN PM.Parameter_ID = 0 THEN 'Returns'
ELSE PM.Name
END AS [ParameterName],
'['+TYPE_NAME(PM.User_Type_ID)+']' AS [ParameterDataType],
CASE 
WHEN TYPE_NAME(PM.User_Type_ID) IN ('float', 'uniqueidentifier', 'datetime', 'bit', 'bigint', 'int', 'image', 'money', 'xml', 'varbinary', 'tinyint', 'text', 'ntext', 'smallint', 'smallmoney') THEN ''
WHEN TYPE_NAME(PM.User_Type_ID) IN ('decimal', 'numeric') THEN '(' + CAST( Precision AS VARCHAR(4) ) + ', ' + CAST( Scale AS VARCHAR(4)) + ')'
ELSE 
case 
when PM.Max_Length <> -1 then '('+CAST( PM.Max_Length AS VARCHAR(4))+')'
when (TYPE_NAME(PM.User_Type_ID) = 'xml') or (pm.system_type_id <> pm.user_type_id) then ''
else '(max)' 
end
END AS [Size],
CASE 
WHEN PM.Is_Output = 1 THEN 'Output'
ELSE 'Input'
END AS [Direction]
FROM sys.objects AS SO
INNER JOIN sys.parameters AS PM ON SO.OBJECT_ID = PM.OBJECT_ID
WHERE TYPE IN ('P','FN') and SO.object_id = OBJECT_ID(@objectname)
ORDER BY [Schema], SO.Name, PM.parameter_id