$Lexer = New-Object PSObject
$Lexer = $Lexer |
Add-Member -PassThru NoteProperty at 0 |
Add-Member -PassThru NoteProperty col 0 |
Add-Member -PassThru NoteProperty ch "" |
Add-Member -PassThru NoteProperty token $null |
Add-Member -PassThru NoteProperty stream $null |
Add-Member -PassThru ScriptMethod initialize {
    param($Path, $Encoding = [System.Text.Encoding]::Default)
    $Path = Resolve-Path $Path
    $this.stream = New-Object System.IO.StreamReader($Path.ProviderPath, $Encoding)
    $this.next() > $null
    $this.at = 0
    $this.col = 0
} |
Add-Member -PassThru ScriptMethod error {
    param($msg)
    throw @{
        at = $this.at
        ch = $this.ch
        message = $msg
    }
} |
Add-Member -PassThru ScriptMethod tokenize {
    param($type, $value, $indent)
    $ret = New-Object PSObject
    $ret = $ret |
    Add-Member -PassThru NoteProperty TYPE $type |
    Add-Member -PassThru NoteProperty VALUE $value |
    Add-Member -PassThru NoteProperty INDENT $indent |
    Add-Member -PassThru NoteProperty AT $this.at
    return $ret
} |
Add-Member -PassThru ScriptMethod next {
    param($c)
    if ($c -and $c -ne $this.ch) { error("unexpected " + $this.ch) }
    if ($this.stream.EndOfStream) { $this.col += 1; $this.ch = ""; return $this.ch }
    $this.at += 1
    $this.col += 1
    $this.ch = [char]$this.stream.read()
    return $this.ch
} |
Add-Member -PassThru ScriptMethod white {
    while($this.ch -eq " ") {
        if ($this.ch -eq "") { break }
        $this.next() > $null
    }
} |
Add-Member -PassThru ScriptMethod comment {
    $this.white()
    if ($this.ch -eq "#") {
        while($this.ch -ne "`r" -and $this.ch -ne "`n") {
            if ($this.ch -eq "") { break }
            $this.next() > $null
        }
    }
} |
Add-Member -PassThru ScriptMethod string {
    param($q)
    $buf = ""
    $this.next() > $null
    while($this.ch -ne $q){
        if ($this.ch -eq "") { $this.error("invalid string") }
        if ($this.ch -eq "\") {
            switch($this.next()){
                "r" { $buf += "`r" }
                "n" { $buf += "`n" }
                "\" { $buf += "\" }
                $q  { $buf += $q }
                default { $buf += " "}
            }
        } else {
            $buf += $this.ch
        }
        $this.next() > $null
    }
    $this.next() > $null
    return $this.tokenize("STRING", $buf, $this.col - $buf.length - 2)
} |
Add-Member -PassThru ScriptMethod raw_string {
    param($buf = "")
    while ($this.ch -ne "`r" -and $this.ch -ne "`n") {
        if ($this.ch -eq "")  { break }
        if ($this.ch -eq "#") { break }
        if ($this.ch -eq "{") { break }
        if ($this.ch -eq "}") { break }
        if ($this.ch -eq "[") { break }
        if ($this.ch -eq "]") { break }
        if ($this.ch -eq ",") { break }
        if ($this.ch -eq ":") {
            $this.next() > $null
            if ($this.ch -eq " " -or $this.ch -eq "`r" -or $this.ch -eq "`n") {
                return $this.tokenize("KEY", $buf.trim(), $this.col - $buf.length - 1) # return
            } else {
                $buf += ":"
            }
        }
        $buf += $this.ch
        $this.next() > $null
    }
    return $this.tokenize("STRING", $buf.trim(), $this.col - $buf.length)
} |
Add-Member -PassThru ScriptMethod newline {
    $buf = ""
    if ($this.ch -eq "`r") {
        $buf += $this.ch
        $this.next() > $null
    }
    if ($this.ch -eq "`n") {
        $buf += $this.ch
        $this.next() > $null
    }
    $this.col = 0
    return $this.tokenize("NEWLINE", $buf, $this.col)
} |
Add-Member -PassThru ScriptMethod nextToken {
    if ($this.token.type -eq "KEY") {
        $this.token = $this.tokenize("COLON", ":", $this.col - 1)
        return $this.token
    }
    $this.white()
    $this.comment()
    switch ($this.ch) {
        ""  {
            $this.next() > $null
            $this.token = $this.tokenize("EOF", $this.ch, $this.col)
        }
        ":" {
            $this.token = $this.tokenize("COLON", $this.ch, $this.col)
            $this.next() > $null
        }
        "-" {
            if ($this.next() -eq " ") {
                $this.token = $this.tokenize("HYPHEN", "-", $this.col - 1)
            } else {
                $this.token = $this.raw_string("-")
            }
        }
        "," {
            $this.token = $this.tokenize("COMMA", $this.ch, $this.col)
            $this.next() > $null
        }
        "[" {
            $this.token = $this.tokenize("LBRACKET", $this.ch, $this.col)
            $this.next() > $null
        }
        "]" {
            $this.token = $this.tokenize("RBRACKET", $this.ch, $this.col)
            $this.next() > $null
        }
        "{" {
            $this.token = $this.tokenize("LBRACE", $this.ch, $this.col)
            $this.next() > $null
        }
        "}" {
            $this.token = $this.tokenize("RBRACE", $this.ch, $this.col)
            $this.next() > $null
        }
        "#" { $this.token = $this.comment() }
        "'" { $this.token = $this.string($this.ch) }
        '"' { $this.token = $this.string($this.ch) }
        "`r" { $this.token = $this.newline() }
        "`n" { $this.token = $this.newline() }
        "&" { $this.error("'&' has been reserved for future") }
        "*" { $this.error("'*' has been reserved for future") }
        default { $this.token = $this.raw_string("") }
    }
    $this.comment()
    return $this.token
}

$Parser = New-Object PSObject
$Parser = $Parser | 
Add-Member -PassThru NoteProperty lexer $null |
Add-Member -PassThru NoteProperty token $null |
Add-Member -PassThru ScriptMethod error {
    param($msg)
    throw @{
        token = $this.token
        message = $msg
    }
} |
Add-Member -PassThru ScriptMethod consume {
    $this.token = $this.lexer.nextToken()
    return $this.token
} |
Add-Member -PassThru ScriptMethod check {
    param($type)
    if ($this.token.type -eq $type) {
        return $true
    } else {
        return $false
    }
} |
Add-Member -PassThru ScriptMethod white {
    while ($this.check("NEWLINE")) {
        $this.consume() > $null
    }
} |
Add-Member -PassThru ScriptMethod next {
    param($type)
    if ($type -and $type -ne $this.token.type) {
        $this.error("type error. expected '$type', but discover " + $this.token.type)
    }
    $this.consume() > $null
    $this.white()
    return $this.token
} |
Add-Member -PassThru ScriptMethod match {
    param($type)
    $this.next($type) > $null
} |
Add-Member -PassThru ScriptMethod stat_FLOW {
    $next = $this.token
    switch ($next.type) {
        "LBRACE" {
            $this.match("LBRACE")
            return $this.stat_FLOW_MAPPING()
        }
        "LBRACKET" {
            $this.match("LBRACKET")
            return $this.stat_FLOW_SEQUENCE()
        }
        "STRING" {
            return $this.stat_STRING()
        }
    }
    $this.error("invalid flow style value. $next")
} |
Add-Member -PassThru ScriptMethod stat_FLOW_MAPPING {
    $result = New-Object System.Collections.Hashtable
    if ($this.check("RBLACE")) {
        $this.match("RBLACE")
        return $result
    }
    $key = $this.stat_KEY()
    $this.match("COLON")
    $result[$key] = $this.stat_FLOW()
    while ($this.check("COMMA")) {
        $this.match("COMMA")
        $key = $this.stat_KEY()
        $this.match("COLON")
        $result[$key] = $this.stat_FLOW()
    }
    if ($this.check("RBRACE")) {
        $this.match("RBRACE")
        return $result
    }
    $this.error("invalid mapping")
} |
Add-Member -PassThru ScriptMethod stat_FLOW_SEQUENCE {
    $result = New-Object System.Collections.ArrayList
    if ($this.check("RBLACKET")) {
        $this.match("RBLACKET")
        return $result
    }
    $result.add($this.stat_FLOW()) > $null
    $next = $this.token
    while($next.type -eq "COMMA"){
        $this.match("COMMA")
        $result.add($this.stat_FLOW()) > $null
        $next = $this.token
    }
    if ($next.type -eq "RBRACKET") {
        $this.match("RBRACKET")
        return $result
    }
    $this.error("invalid sequence")
} |
Add-Member -PassThru ScriptMethod tran_STRING {
    param($token)
    $double = New-Object System.Double
    $datetime = New-Object System.DateTime
    switch ($token.value) {
        "true" { return $true }
        "false" { return $false }
        "yes" { return $true }
        "no" { return $false }
        "on" { return $true }
        "off" { return $false }
        "null" { return $null }
        "nil" { return $null }
        {[Double]::TryParse($token.value, [ref]$double)} {
            return $double
        }
        {[Datetime]::TryParse($token.value, [ref]$datetime)} {
            return $datetime
        }
        default { return $token.value }
    }
} |
Add-Member -PassThru ScriptMethod tran_KEY {
    param ($token)
    $hold = $token.value
    $value = $this.tran_STRING($token)
    if ($value -eq $null) {
        return $hold # cant use null as KEY, return STRING 'null'
    } else {
        return $value
    }
} |
Add-Member -PassThru ScriptMethod stat_STRING {
    $token = $this.token
    $this.match("STRING")
    $this.white()
    return $this.tran_STRING($token)
} |
Add-Member -PassThru ScriptMethod stat_KEY {
    $next = $this.token
    $this.next() > $null
    $this.white()
    return $this.tran_KEY($next)
} |
Add-Member -PassThru ScriptMethod stat_MAPPING {
    param($token)
    $result = New-Object System.Collections.Hashtable
    $level = $token.indent
    $key = $this.tran_KEY($token) # transform token
    while($true){
        $next = $this.next("COLON")
        # add
        if ($next.indent -lt $level) {
            $result[$key] = $null
        } elseif ($next.indent -eq $level) {
            $result[$key] = $null
        } elseif ($next.indent -gt $level) {
            $result[$key] = $this.stat_VALUE()
            $next = $this.token
        }
        # next loop?
        if ($next.indent -lt $level -or $next.type -eq "EOF") {
            break
        } elseif ($next.indent -eq $level) {
            # next loop
            $key = $this.stat_KEY($next)
            $next = $this.token
        } else {
            $this.error("invalid mapping. $next")
        }
    }
    $this.white()
    return $result
} |
Add-Member -PassThru ScriptMethod stat_SEQUENCE {
    param($hyphen)
    if ($hyphen.type -ne "HYPHEN") { $this.error("invalid sequence. $hyphen") }
    $level = $hyphen.indent
    $result = New-Object System.Collections.ArrayList
    $next = $this.token # expect list value(not hyphen)
    while($true){
        # add value
        if ($next.indent -lt $level -or $next.type -eq "EOF") {
            $result.add($null) > $null
        } elseif ($next.indent -eq $level -and $next.type -eq "HYPHEN") {
            $result.add($null) > $null
        } elseif ($next.indent -gt $level) {
            $result.add($this.stat_VALUE()) > $null
            $next = $this.token
        }
        # next loop?
        if ($next.indent -lt $level -or $next.type -eq "EOF") {
            break
        } elseif ($next.indent -eq $level -and $next.type -eq "HYPHEN") {
            # continue next loop
            $next = $this.next("HYPHEN")
        } else {
            $this.error("invalid sequence")
        }
    }
    $this.white()
    return $result
} |
Add-Member -PassThru ScriptMethod stat_VALUE {
    $curr = $this.token
    $next = $this.next()
    if ($next.type -eq "COLON") {
        return $this.stat_MAPPING($curr)
    }
    switch ($curr.type) {
        "LBRACE" { return $this.stat_FLOW_MAPPING() }
        "LBRACKET" { return $this.stat_FLOW_SEQUENCE() }
        "HYPHEN" { return $this.stat_SEQUENCE($curr) }
        default { return $this.tran_String($curr) }
    }
} |
Add-Member -PassThru ScriptMethod stat_YAML {
    $result = $this.stat_VALUE()
    # check
    $this.white()
    $next = $this.token
    if ($next.type -ne "EOF") {
        $this.error("invalid YAML. Found $next.")
    }
    return $result
} |
Add-Member -PassThru ScriptMethod run {
    # initialize
    param($Lexer)
    $this.lexer = $Lexer
    $this.token = $this.lexer.nextToken()

    # parse yaml
    $result = $this.stat_YAML()
    return $result
}

function hoge {
    # test for Lexer
    try {
        $Lexer.initialize(".\test.yml")
        $Lexer.nextToken()
        while($Lexer.token.type -ne "EOF") {
            $Lexer.nextToken()
        }
        $Lexer.stream.Close()
    } catch {
        Write-Error $_
    } finally {
        $Lexer.stream.Close()
    }
}

function fuga {
    # test for Parser
    try {
        $Lexer.initialize(".\test.yml")
        $Parser.run($Lexer)
        $Lexer.stream.Close()
    } catch {
        Write-Error $_
    } finally {
        $Lexer.stream.Close()
    }
}

function Import-YAML {
    param($Path, $Encoding = [Text.Encoding]::Default)
    $Path = Resolve-Path $Path
    try {
        $Lexer.initialize($Path.ProviderPath, $Encoding)
        $Parser.run($Lexer)
        $Lexer.stream.Close()
    } catch {
        Write-Error $_ 
    } finally {
        $Lexer.stream.Close()
    }
}

Export-ModuleMember -Function Import-YAML
