## 🚀 Quick Start (1 comando)

Execute diretamente via PowerShell (sem download manual):

```powershell
iex (iwr "https://raw.githubusercontent.com/julianscunha/Veeam.VBR.ASBuilt/main/run.ps1" -UseBasicParsing)
```

### 🔧 Com parâmetros

```powershell
iex (iwr "https://raw.githubusercontent.com/julianscunha/Veeam.VBR.ASBuilt/main/run.ps1" -UseBasicParsing) -Mode DownloadOnly
```

---

## ▶️ Run in PowerShell

[![Run in PowerShell](https://img.shields.io/badge/Run%20in-PowerShell-blue?logo=powershell)](https://raw.githubusercontent.com/julianscunha/Veeam.VBR.ASBuilt/main/run.ps1)

---

## ℹ️ Como funciona

- Bootstrap baixa automaticamente o script principal
- Cria `modules` e `report`
- Executa no diretório atual (sem usar TEMP)

---

## ⚠️ Observações

- Requer internet para bootstrap
- Offline: usar previamente `-Mode DownloadOnly`
