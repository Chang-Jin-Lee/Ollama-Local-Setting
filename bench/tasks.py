# 10 coding tasks with hidden tests. Each: (id, prompt, test_code)
TASKS = [
("lru_cache", """Python으로 클래스 `LRUCache`를 구현하세요. `__init__(self, capacity)`, `get(self, key) -> int` (없으면 -1), `put(self, key, value)`. get/put 모두 평균 O(1)이어야 합니다. 코드만 ```python 블록으로 출력하세요.""",
"""
c = LRUCache(2)
c.put(1,1); c.put(2,2)
assert c.get(1) == 1
c.put(3,3)
assert c.get(2) == -1
c.put(4,4)
assert c.get(1) == -1 and c.get(3) == 3 and c.get(4) == 4
c2 = LRUCache(1); c2.put(5,5); c2.put(5,7)
assert c2.get(5) == 7
"""),

("longest_valid_parens", """Python 함수 `longest_valid_parentheses(s: str) -> int`를 구현하세요. '(' 와 ')' 로만 이루어진 문자열에서 가장 긴 올바른 괄호 부분문자열의 길이를 반환합니다. 코드만 ```python 블록으로 출력하세요.""",
"""
assert longest_valid_parentheses("(()") == 2
assert longest_valid_parentheses(")()())") == 4
assert longest_valid_parentheses("") == 0
assert longest_valid_parentheses("()(()") == 2
assert longest_valid_parentheses("()(())") == 6
assert longest_valid_parentheses("(()))())(") == 4
"""),

("median_two_sorted", """Python 함수 `find_median_sorted_arrays(a: list[int], b: list[int]) -> float`를 구현하세요. 두 정렬된 배열의 중앙값을 O(log(min(m,n)))에 구해야 합니다. 코드만 ```python 블록으로 출력하세요.""",
"""
assert find_median_sorted_arrays([1,3],[2]) == 2.0
assert find_median_sorted_arrays([1,2],[3,4]) == 2.5
assert find_median_sorted_arrays([],[1]) == 1.0
assert find_median_sorted_arrays([0,0],[0,0]) == 0.0
assert find_median_sorted_arrays([1,2,3,4,5,6],[7,8,9]) == 5.0
import random
for _ in range(200):
    m=[random.randint(-50,50) for _ in range(random.randint(0,8))]
    n=[random.randint(-50,50) for _ in range(random.randint(1,8))]
    m.sort(); n.sort(); all_=sorted(m+n); k=len(all_)
    exp = all_[k//2] if k%2 else (all_[k//2-1]+all_[k//2])/2
    assert abs(find_median_sorted_arrays(m,n)-exp) < 1e-9, (m,n)
"""),

("calc", """Python 함수 `evaluate(expr: str) -> int`를 구현하세요. `+ - * /`, 괄호, 공백, 음수 단항 부호를 지원하는 정수 사칙연산 계산기입니다. 나눗셈은 0 방향으로 절삭합니다(예: -7/2 == -3). eval()이나 ast 모듈을 쓰지 말고 직접 파싱하세요. 코드만 ```python 블록으로 출력하세요.""",
"""
assert evaluate("1 + 1") == 2
assert evaluate(" 6-4 / 2 ") == 4
assert evaluate("2*(5+5*2)/3+(6/2+8)") == 21
assert evaluate("(2+6* 3+5- (3*14/7+2)*5)+3") == -12
assert evaluate("-7/2") == -3
assert evaluate("-(3+4)*2") == -14
"""),

("serialize_tree", """Python으로 이진트리 직렬화/역직렬화를 구현하세요. 노드 클래스는 `class TreeNode: def __init__(self, val=0, left=None, right=None)` 형태로 정의하고, 함수 `serialize(root) -> str` 와 `deserialize(data: str) -> TreeNode` 를 구현하세요. 코드만 ```python 블록으로 출력하세요.""",
"""
def same(a,b):
    if a is None and b is None: return True
    if a is None or b is None: return False
    return a.val==b.val and same(a.left,b.left) and same(a.right,b.right)
t = TreeNode(1, TreeNode(2), TreeNode(3, TreeNode(4), TreeNode(5)))
assert same(deserialize(serialize(t)), t)
assert deserialize(serialize(None)) is None
single = TreeNode(-9)
assert same(deserialize(serialize(single)), single)
deep = TreeNode(1); cur = deep
for i in range(2, 30):
    cur.left = TreeNode(i); cur = cur.left
assert same(deserialize(serialize(deep)), deep)
"""),

("stock_k", """Python 함수 `max_profit(k: int, prices: list[int]) -> int`를 구현하세요. 최대 k번 매수/매도(동시에 한 주식만 보유)로 얻을 수 있는 최대 이익을 반환합니다. 코드만 ```python 블록으로 출력하세요.""",
"""
assert max_profit(2,[2,4,1]) == 2
assert max_profit(2,[3,2,6,5,0,3]) == 7
assert max_profit(0,[1,3]) == 0
assert max_profit(100,[1,2,3,4,5]) == 4
assert max_profit(1,[7,6,4,3,1]) == 0
assert max_profit(3,[1,7,2,8,3,9]) == 18
"""),

("regex", """Python 함수 `is_match(s: str, p: str) -> bool`를 구현하세요. '.'(임의의 한 문자)와 '*'(직전 문자의 0회 이상 반복)를 지원하는 정규식 매칭이며, 패턴은 문자열 전체와 매칭되어야 합니다. re 모듈을 쓰지 마세요. 코드만 ```python 블록으로 출력하세요.""",
"""
assert is_match("aa","a") == False
assert is_match("aa","a*") == True
assert is_match("ab",".*") == True
assert is_match("aab","c*a*b") == True
assert is_match("mississippi","mis*is*p*.") == False
assert is_match("","") == True
assert is_match("","a*") == True
assert is_match("abc","") == False
"""),

("toposort", """Python 함수 `topo_sort(n: int, edges: list[tuple[int,int]]) -> list[int] | None`를 구현하세요. 0..n-1 노드의 방향 그래프에서 위상정렬 결과를 반환하고, 사이클이 있으면 None을 반환합니다. 같은 조건이면 번호가 작은 노드를 먼저 배치하세요. 코드만 ```python 블록으로 출력하세요.""",
"""
assert topo_sort(4,[(0,1),(0,2),(1,3),(2,3)]) == [0,1,2,3]
assert topo_sort(2,[(0,1),(1,0)]) is None
assert topo_sort(3,[]) == [0,1,2]
r = topo_sort(6,[(5,2),(5,0),(4,0),(4,1),(2,3),(3,1)])
assert r is not None and all(r.index(a) < r.index(b) for a,b in [(5,2),(5,0),(4,0),(4,1),(2,3),(3,1)])
assert topo_sort(1,[(0,0)]) is None
"""),

("word_break", """Python 함수 `word_break(s: str, words: list[str]) -> list[str]`를 구현하세요. s를 words의 단어들로 분해하는 모든 방법을 "단어 단어 단어" 형태 문자열 리스트로 반환합니다(순서 무관). 코드만 ```python 블록으로 출력하세요.""",
"""
assert sorted(word_break("catsanddog",["cat","cats","and","sand","dog"])) == sorted(["cats and dog","cat sand dog"])
assert sorted(word_break("pineapplepenapple",["apple","pen","applepen","pine","pineapple"])) == sorted(["pine apple pen apple","pineapple pen apple","pine applepen apple"])
assert word_break("catsandog",["cats","dog","sand","and","cat"]) == []
assert word_break("aaa",["a","aa"]) != []
"""),

("thread_safe_counter", """Python으로 클래스 `RateLimiter`를 구현하세요. `__init__(self, max_calls: int, period: float)` 이고 `allow(self, now: float) -> bool` 은 슬라이딩 윈도우 방식으로 최근 period 초 안에 허용된 호출이 max_calls 미만이면 True(그리고 호출 기록), 아니면 False를 반환합니다. threading.Lock으로 스레드 안전해야 합니다. 코드만 ```python 블록으로 출력하세요.""",
"""
r = RateLimiter(3, 1.0)
assert r.allow(0.0) and r.allow(0.1) and r.allow(0.2)
assert not r.allow(0.3)
assert r.allow(1.05)
r2 = RateLimiter(1, 10.0)
assert r2.allow(100.0)
assert not r2.allow(105.0)
assert r2.allow(110.5)
import threading
r3 = RateLimiter(50, 1000.0)
res = []
def w():
    for i in range(20): res.append(r3.allow(1.0))
ts=[threading.Thread(target=w) for _ in range(5)]
[t.start() for t in ts]; [t.join() for t in ts]
assert sum(res) == 50, sum(res)
"""),
]
