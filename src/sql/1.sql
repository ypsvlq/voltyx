PRAGMA application_id=0x766C7478;

CREATE TABLE chart(
  id INTEGER PRIMARY KEY,
  level INTEGER NOT NULL,
  difficulty INTEGER NOT NULL,
  effector TEXT NOT NULL,
  illustrator TEXT NOT NULL
);

CREATE TABLE song(
  id INTEGER PRIMARY KEY,
  hash INTEGER NOT NULL,
  name TEXT,
  title TEXT NOT NULL,
  artist TEXT NOT NULL,
  bpm TEXT NOT NULL,
  preview REAL NOT NULL,
  chart1 INTEGER REFERENCES chart,
  chart2 INTEGER REFERENCES chart,
  chart3 INTEGER REFERENCES chart,
  chart4 INTEGER REFERENCES chart
);
