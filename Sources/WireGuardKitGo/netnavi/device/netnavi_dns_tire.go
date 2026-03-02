
/**
 * Copyright (C) 2025- Freecomm US. All Rights Reserved.
 */
package device

import (
    "bufio"
    "github.com/miekg/dns"
    "github.com/bits-and-blooms/bloom/v3"
    "log"
    "os"
    "strings"
    "sync"
    "time"
)

// ------------------- Reverse Trie -------------------

type TrieNode struct {
    children map[string]*TrieNode
    isEnd    bool
}

func NewTrieNode() *TrieNode {
    return &TrieNode{children: make(map[string]*TrieNode)}
}

type ReverseTrie struct {
    root *TrieNode
    mu   sync.RWMutex
}

func NewReverseTrie() *ReverseTrie {
    return &ReverseTrie{root: NewTrieNode()}
}

func (t *ReverseTrie) Insert(domain string) {
    t.mu.Lock()
    defer t.mu.Unlock()

    parts := strings.Split(domain, ".")
    reverse(parts)
    node := t.root
    for _, p := range parts {
        if _, ok := node.children[p]; !ok {
            node.children[p] = NewTrieNode()
        }
        node = node.children[p]
    }
    node.isEnd = true
}

func (t *ReverseTrie) Match(domain string) bool {
    t.mu.RLock()
    defer t.mu.RUnlock()

    parts := strings.Split(domain, ".")
    reverse(parts)
    node := t.root
    for _, p := range parts {
        if node.isEnd {
            return true
        }
        child, ok := node.children[p]
        if !ok {
            return false
        }
        node = child
    }
    return node.isEnd
}

func reverse(s []string) {
    for i, j := 0, len(s)-1; i < j; i, j = i+1, j-1 {
        s[i], s[j] = s[j], s[i]
    }
}

// ------------------- DNS Proxy -------------------

type DNSProxy struct {
    BindAddr           string
    UpstreamNetNavi    string
    UpstreamLocal    string
    BlacklistDomainFile    string
    NetNavOptimizationDomainFile    string
    LocalDomainFile    string

    filterBlacklistDomains       *bloom.BloomFilter
    wildcardTrieBlackListDomains *ReverseTrie

    filterNetNavOptimizationDomains       *bloom.BloomFilter
    wildcardTrieNetNavOptimizationDomains *ReverseTrie

    filterLocalDomains       *bloom.BloomFilter
    wildcardTrieLocalDomains *ReverseTrie

    udpServer *dns.Server
    tcpServer *dns.Server
    stopCh    chan struct{}
    wg        sync.WaitGroup
}

func NewDNSProxy(bindAddr, upstreamNetNavi, upstreamLocal, blacklistDomainFile, netNavOptimizationDomainFile, localDomainFile string) *DNSProxy {
    return &DNSProxy{
        BindAddr:   bindAddr,
        UpstreamNetNavi:  upstreamNetNavi,
        UpstreamLocal:  upstreamLocal,
        BlacklistDomainFile: blacklistDomainFile,
        NetNavOptimizationDomainFile: netNavOptimizationDomainFile,
        LocalDomainFile: localDomainFile,
        stopCh:     make(chan struct{}),
    }
}

// Load blacklist domains into Bloom filter and wildcard trie
func (p *DNSProxy) loadBlackListDomains() error {
    f, err := os.Open(p.BlacklistDomainFile)
    if err != nil {
        return err
    }
    defer f.Close()

    p.filterBlacklistDomains = bloom.NewWithEstimates(10_000_000, 0.01)
    p.wildcardTrieBlackListDomains = NewReverseTrie()

    scanner := bufio.NewScanner(f)
    for scanner.Scan() {
        d := strings.ToLower(strings.TrimSpace(scanner.Text()))
        if d == "" {
            continue
        }
        if strings.HasPrefix(d, "*.") {
            p.wildcardTrieBlackListDomains.Insert(d[2:])
        } else {
            p.filterBlacklistDomains.AddString(d)
        }
    }
    return scanner.Err()
}

// Load NetNavi default domains into Bloom filter and wildcard trie
func (p *DNSProxy) loadNetNaviOptimizationDomainFile() error {
    f, err := os.Open(p.NetNavOptimizationDomainFile)
    if err != nil {
        return err
    }
    defer f.Close()

    p.filterNetNavOptimizationDomains = bloom.NewWithEstimates(10_000_000, 0.01)
    p.wildcardTrieNetNavOptimizationDomains = NewReverseTrie()

    scanner := bufio.NewScanner(f)
    for scanner.Scan() {
        d := strings.ToLower(strings.TrimSpace(scanner.Text()))
        if d == "" {
            continue
        }
        if strings.HasPrefix(d, "*.") {
            p.wildcardTrieNetNavOptimizationDomains.Insert(d[2:])
        } else {
            p.filterNetNavOptimizationDomains.AddString(d)
        }
    }
    return scanner.Err()
}

// Load local domains into Bloom filter and wildcard trie
func (p *DNSProxy) loadLocalDomains() error {
    f, err := os.Open(p.LocalDomainFile)
    if err != nil {
        return err
    }
    defer f.Close()

    p.filterLocalDomains = bloom.NewWithEstimates(10_000_000, 0.01)
    p.wildcardTrieLocalDomains = NewReverseTrie()

    scanner := bufio.NewScanner(f)
    for scanner.Scan() {
        d := strings.ToLower(strings.TrimSpace(scanner.Text()))
        if d == "" {
            continue
        }
        if strings.HasPrefix(d, "*.") {
            p.wildcardTrieLocalDomains.Insert(d[2:])
        } else {
            p.filterLocalDomains.AddString(d)
        }
    }
    return scanner.Err()
}

// Match blacklist against Bloom filter + wildcard trie
func (p *DNSProxy) matchBlacklistDomain(domain string) bool {
    domain = strings.ToLower(domain)
    if p.filterBlacklistDomains != nil && p.filterBlacklistDomains.TestString(domain) {
        return true
    }
    if p.wildcardTrieBlackListDomains != nil && p.wildcardTrieBlackListDomains.Match(domain) {
        return true
    }
    return false
}

// Match NetNaviDefault against Bloom filter + wildcard trie
func (p *DNSProxy) matchNetNaviDefaultDomain(domain string) bool {
    domain = strings.ToLower(domain)
    if p.filterNetNavOptimizationDomains != nil && p.filterNetNavOptimizationDomains.TestString(domain) {
        return true
    }
    if p.wildcardTrieNetNavOptimizationDomains != nil && p.wildcardTrieNetNavOptimizationDomains.Match(domain) {
        return true
    }
    return false
}

// Match domain against Bloom filter + wildcard trie
func (p *DNSProxy) matchLocalDomain(domain string) bool {
    domain = strings.ToLower(domain)
    if p.filterLocalDomains != nil && p.filterLocalDomains.TestString(domain) {
        return true
    }
    if p.wildcardTrieLocalDomains != nil && p.wildcardTrieLocalDomains.Match(domain) {
        return true
    }
    return false
}

// Handle DNS request
func (p *DNSProxy) handleDNSRequest(w dns.ResponseWriter, req *dns.Msg) {
    if len(req.Question) == 0 {
        return
    }
    q := req.Question[0]
    domain := strings.TrimSuffix(q.Name, ".")
    domain = strings.TrimPrefix(domain, "www.")

    if p.matchBlacklistDomain(domain) {
        log.Printf("[dnsproxy] blocked blacklisted domain: %s", domain)
        m := new(dns.Msg)
        m.SetRcode(req, dns.RcodeNameError) // NXDOMAIN
        _ = w.WriteMsg(m)
        return
    }

    upstream := p.UpstreamNetNavi
    if p.matchNetNaviDefaultDomain(domain) {
        log.Printf("[dnsproxy] netnavi optimization matched %s going through %s", domain, upstream)
        goto dnsStart
    }

    if p.matchLocalDomain(domain) {
        upstream = p.UpstreamLocal
        log.Printf("[dnsproxy] local matched %s going through %s", domain, upstream)
        goto dnsStart
    }

    log.Printf("[dnsproxy] default %s going through %s", domain, upstream)

dnsStart:
    c := &dns.Client{Net: "udp"}
    reqCopy := req.Copy()
    resp, _, err := c.Exchange(reqCopy, upstream)
    if err != nil {
        // Optional: fallback for servers that reject EDNS0
        noEDNS := req.Copy()
        noEDNS.SetEdns0(0, false)
        resp, _, err = c.Exchange(noEDNS, upstream)
        if err != nil {
            m := new(dns.Msg)
            m.SetRcode(req, dns.RcodeServerFailure)
            _ = w.WriteMsg(m)
            return
        }
    }
    resp.Id = req.Id
    log.Printf("[dnsproxy] query response for %s: %v from %s", domain, resp.Rcode, upstream)
    _ = w.WriteMsg(resp)
}

// Start proxy (blocking on UDP, TCP in background)
func (p *DNSProxy) Start() error {
    loadStartTime := time.Now().UnixMilli()
    if err := p.loadLocalDomains(); err != nil {
        return err
    }
    if err := p.loadNetNaviOptimizationDomainFile(); err != nil {
        return err
    }
    if err := p.loadBlackListDomains(); err != nil {
        return err
    }
    log.Printf("[dnsproxy] Loading Domains done in %v ms!", time.Now().UnixMilli() - loadStartTime)

    dns.HandleFunc(".", p.handleDNSRequest)

    p.udpServer = &dns.Server{Addr: p.BindAddr, Net: "udp"}
    p.tcpServer = &dns.Server{Addr: p.BindAddr, Net: "tcp"}

    p.wg.Add(1)
    go func() {
        defer p.wg.Done()
        if err := p.tcpServer.ListenAndServe(); err != nil {
            log.Printf("[dnsproxy] TCP server stopped: %v", err)
        }
    }()

    log.Printf("[dnsproxy] started on %s → NetNavi Default DNS:%s / Matched Local DNS:%s", p.BindAddr, p.UpstreamNetNavi, p.UpstreamLocal)

    if err := p.udpServer.ListenAndServe(); err != nil {
        select {
        case <-p.stopCh:
            return nil
        default:
            return err
        }
    }
    return nil
}

// Stop gracefully shuts down servers
func (p *DNSProxy) Stop() {
    close(p.stopCh)
    if p.udpServer != nil {
        _ = p.udpServer.Shutdown()
    }
    if p.tcpServer != nil {
        _ = p.tcpServer.Shutdown()
    }
    p.wg.Wait()
    log.Println("[dnsproxy] stopped")
}

